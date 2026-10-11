/**
 * searxng — standalone web search for pi via a self-hosted SearXNG instance.
 *
 * Owns the `web_search` tool (extracted from vision-web). Docker container
 * lifecycle, retries, multi-instance fallback and a DuckDuckGo HTML fallback
 * live in docker.ts / search.ts / fetch.ts (all pi-independent, testable).
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { loadConfig, type Config } from "./config.js";
import {
  baseUrlFor,
  cancelIdleStop,
  containerLogs,
  containerStatus,
  ensureReady,
  isDockerAvailable,
  scheduleIdleStop,
  stopContainer,
  type DockerConfig,
} from "./docker.js";
import { searxngSearch } from "./search.js";
import { fetchWebPage } from "./fetch.js";

export default function (pi: ExtensionAPI) {
  const config: Config = loadConfig();
  const dockerCfg: DockerConfig = {
    image: config.dockerImage,
    containerName: config.containerName,
    port: config.dockerPort,
  };
  const idleMs = () => Math.max(1, config.dockerIdleMinutes) * 60 * 1000;

  pi.on("session_shutdown", () => {
    cancelIdleStop();
    if (config.stopOnShutdown) stopContainer(config.containerName).catch(() => {});
  });

  pi.on("session_start", async (_event, ctx) => {
    if (!config.enabled) return;
    if (config.warmupOnStart && !config.baseUrl && config.dockerEnabled) {
      const url = await ensureReady(dockerCfg, ctx.signal).catch(() => null);
      if (url) scheduleIdleStop(config.containerName, idleMs());
      else if (ctx.hasUI) ctx.ui.notify("searxng: warmup failed (Docker unavailable?). Search will retry on demand.", "info");
    } else if (ctx.hasUI && !config.baseUrl && !config.dockerEnabled) {
      ctx.ui.notify(
        "searxng: no search backend configured. Set baseUrl in extensions/searxng/config.json or enable dockerEnabled.",
        "info",
      );
    }
  });

  // ------------------------------------------------------------------ tools

  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Search the web using a self-hosted SearXNG instance. Returns ranked results with title, URL, and snippet. Optionally fetch page content for the top results.",
    promptSnippet: "Search the web for: ",
    parameters: Type.Object({
      query: Type.String({ description: "Search query. Use 2-4 varied angles for broad coverage." }),
      numResults: Type.Optional(Type.Number({ description: "Number of results (1-20, default 5)." })),
      domainFilter: Type.Optional(
        Type.Array(Type.String({ description: "Restrict results to these domains. Prefix with - to exclude, e.g. \"-reddit.com\"." })),
      ),
      recencyFilter: Type.Optional(
        Type.Union(
          [Type.Literal("day"), Type.Literal("week"), Type.Literal("month"), Type.Literal("year")],
          { description: "Accepted but NOT applied: reliable engines lack time_range support (requesting it returns zero results)." },
        ),
      ),
      includeContent: Type.Optional(
        Type.Boolean({ description: "Also fetch readable markdown content for the top results (default false)." }),
      ),
    }),
    async execute(_toolCallId, params, signal, _onUpdate, _ctx) {
      try {
        return await runSearch(config, dockerCfg, params, signal);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        return { content: [{ type: "text", text: `Web search failed: ${msg.slice(0, 500)}` }], details: { error: msg } };
      }
    },
  });

  // -------------------------------------------------------------- command

  pi.registerCommand("searxng", {
    description: "SearXNG search backend: status, start, stop, logs.",
    handler: async (args, ctx) => {
      const sub = (args ?? "").trim().split(/\s+/)[0] ?? "";
      const st = await containerStatus(config.containerName, config.dockerPort);
      const docker = await isDockerAvailable();
      switch (sub) {
        case "start": {
          if (config.baseUrl) {
            ctx.ui.notify(`searxng: using explicit baseUrl ${config.baseUrl} (docker not used).`, "info");
            break;
          }
          if (!config.dockerEnabled) {
            ctx.ui.notify("searxng: dockerEnabled is false. Set baseUrl or enable docker.", "info");
            break;
          }
          const url = await ensureReady(dockerCfg, ctx.signal).catch(() => null);
          if (url) {
            scheduleIdleStop(config.containerName, idleMs());
            ctx.ui.notify(`searxng: container running at ${url}.`, "info");
          } else {
            ctx.ui.notify("searxng: failed to start container. Is Docker running?", "info");
          }
          break;
        }
        case "stop": {
          cancelIdleStop();
          await stopContainer(config.containerName);
          ctx.ui.notify("searxng: container stopped.", "info");
          break;
        }
        case "logs": {
          const tail = Number((args ?? "").trim().split(/\s+/)[1]) || 30;
          ctx.ui.notify(await containerLogs(config.containerName, tail), "info");
          break;
        }
        case "status":
        default: {
          const lines = [
            "searxng status",
            `enabled: ${config.enabled}`,
            `backend: ${config.baseUrl ? `explicit ${config.baseUrl}` : config.dockerEnabled ? `docker (port ${config.dockerPort}, idle ${config.dockerIdleMinutes}m)` : "none configured"}`,
            `docker: ${docker ? "available" : "UNAVAILABLE"} · container: ${st.running ? `running at ${st.url}` : st.present ? "present but not running" : "not present"}`,
            `categories: ${config.categories} · default results: ${config.defaultNumResults} · retries: ${config.maxRetries}`,
            `fallbacks: ${config.fallbackInstances.length > 0 ? config.fallbackInstances.join(", ") : "none"} · ddg-html: ${config.ddgHtmlFallback ? "on" : "off"}`,
          ];
          ctx.ui.notify(lines.join("\n"), "info");
          break;
        }
      }
    },
  });
}

async function runSearch(
  config: Config,
  dockerCfg: DockerConfig,
  params: { query: string; numResults?: number; domainFilter?: string[]; recencyFilter?: string; includeContent?: boolean },
  signal: AbortSignal | undefined,
) {
  if (!config.enabled) {
    return { content: [{ type: "text", text: "Web search disabled (searxng.enabled = false)." }], details: {} };
  }
  const instances: string[] = [];
  let viaDocker = false;
  if (config.baseUrl) {
    instances.push(config.baseUrl);
  } else if (config.dockerEnabled) {
    const dockerUrl = await ensureReady(dockerCfg, signal);
    if (dockerUrl) {
      instances.push(dockerUrl);
      viaDocker = true;
    }
  }
  instances.push(...config.fallbackInstances.filter((u) => !instances.includes(u)));

  if (instances.length === 0) {
    const docker = await isDockerAvailable();
    return {
      content: [
        {
          type: "text",
          text:
            "Web search unavailable: no SearXNG instance. " +
            (config.dockerEnabled
              ? `Docker container failed to start (docker ${docker ? "is available" : "is NOT available"}). Check /searxng status and /searxng logs.`
              : 'Set "baseUrl" in ~/.pi/agent/extensions/searxng/config.json or enable "dockerEnabled".'),
        },
      ],
      details: {},
    };
  }

  const includeDomains: string[] = [];
  const excludeDomains: string[] = [];
  for (const raw of params.domainFilter ?? []) {
    const trimmed = raw.trim();
    if (!trimmed) continue;
    if (trimmed.startsWith("-")) excludeDomains.push(trimmed.slice(1));
    else includeDomains.push(trimmed);
  }

  const outcome = await searxngSearch(
    {
      query: params.query,
      numResults: params.numResults ?? config.defaultNumResults,
      includeDomains: includeDomains.length > 0 ? includeDomains : undefined,
      excludeDomains: excludeDomains.length > 0 ? excludeDomains : undefined,
      recencyLabel: params.recencyFilter,
      signal,
    },
    config,
    instances,
  );

  if (viaDocker) scheduleIdleStop(config.containerName, Math.max(1, config.dockerIdleMinutes) * 60 * 1000);

  const header =
    `Search results for "${params.query}"` +
    (viaDocker ? " (via local Docker)" : outcome.instance ? ` (via ${outcome.instance})` : "") +
    ":";
  const warnBlock = outcome.warnings.length > 0 ? `\n\nNote: ${outcome.warnings.join(" ")}` : "";
  const body = outcome.results.length > 0 ? `\n\n${outcome.answer}` : "\n\nNo results found. Try rephrasing the query or broadening the terms.";

  let fetched = "";
  if (params.includeContent && outcome.results.length > 0) {
    const pages = await Promise.all(
      outcome.results.slice(0, config.maxInlineFetch).map((r) => fetchWebPage(r.url, signal)),
    );
    const parts: string[] = [];
    for (const page of pages) {
      if (page.error) continue;
      parts.push(`## ${page.title || page.url}\n${page.content.slice(0, config.maxFetchChars)}`);
    }
    if (parts.length > 0) fetched = `\n\n--- Page content ---\n${parts.join("\n\n---\n\n")}`;
  }

  return {
    content: [{ type: "text", text: header + warnBlock + body + fetched }],
    details: {
      results: outcome.results.map((r) => ({ title: r.title, url: r.url, snippet: r.snippet })),
      warnings: outcome.warnings,
      instance: outcome.instance,
    },
  };
}

