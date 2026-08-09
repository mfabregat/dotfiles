// Stress test + unit tests for the devcontainer-bash extension.
// Loads the REAL extension module via jiti (same loader pi uses) and runs:
//   unit tests (pure functions) + integration tests against the running
//   devcontainer (docker exec, timeouts, aborts, truncation, concurrency...).
//
// Run:  node test/dcb-test.mjs   (from the extension dir, or any cwd)

import { createRequire } from "node:module";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { existsSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { inspect } from "node:util";

const require = createRequire(import.meta.url);
const HERE = dirname(fileURLToPath(import.meta.url));
const EXT_DIR = join(HERE, "..");
const EXT = join(EXT_DIR, "index.ts");
const WORKSPACE = "/home/marc/Documents/code/tecnalia/humanoids/g1_ws";

const jitiPath = require.resolve("jiti", {
  paths: ["/home/marc/.local/lib/node_modules/@earendil-works/pi-coding-agent/node_modules"],
});
const { createJiti } = require(jitiPath);
const jiti = createJiti(import.meta.url);
const ext = jiti(EXT);
// pi's package is ESM; plain require (through the extension's node_modules
// symlink) returns the named exports directly.
const piPkg = require(join(EXT_DIR, "node_modules", "@earendil-works", "pi-coding-agent"));

let passed = 0;
let failed = 0;
const failures = [];

function ok(name, cond, extra) {
  if (cond) {
    passed++;
    console.log(`  \x1b[32mPASS\x1b[0m ${name}`);
  } else {
    failed++;
    failures.push(name);
    console.log(`  \x1b[31mFAIL\x1b[0m ${name}${extra !== undefined ? " — " + inspect(extra, { depth: 3 }) : ""}`);
  }
}

function section(name) {
  console.log(`\n\x1b[1m${name}\x1b[0m`);
}

// --- container helpers ------------------------------------------------------

function inContainer(cmd) {
  try {
    return execFileSync("docker", ["exec", "g1_ws", "bash", "-lc", cmd], { encoding: "utf8" }).trim();
  } catch (e) {
    return `__ERROR__: ${String(e.stdout ?? "")} ${String(e.stderr ?? e.message).trim().slice(0, 200)}`;
  }
}

const NOISE = /cannot set terminal process group|no job control in this shell/;

// ===========================================================================
section("Unit: config & discovery");
// ===========================================================================

{
  const { findWorkspaceRoot, loadMergedConfig } = ext;
  ok("findWorkspaceRoot finds g1_ws from subdir", findWorkspaceRoot(join(WORKSPACE, "docs")) === WORKSPACE);
  ok("findWorkspaceRoot inert outside", findWorkspaceRoot("/tmp") === null);
  const cfg = loadMergedConfig(WORKSPACE);
  ok("loadMergedConfig returns object with enabled", typeof cfg === "object" && typeof cfg.enabled === "boolean");
}

// ===========================================================================
section("Unit: ${localEnv:X} substitution (the critical fix)");
// ===========================================================================

{
  const { resolveEnvSubstitution, resolveUser } = ext;
  ok("${localEnv:USER} → host USER", resolveEnvSubstitution("${localEnv:USER}") === process.env.USER);
  ok("${env:USER} → host USER", resolveEnvSubstitution("${env:USER}") === process.env.USER);
  ok("${localEnv:UNSET_VAR_XYZ} → null", resolveEnvSubstitution("${localEnv:UNSET_VAR_XYZ}") === null);
  ok("${containerWorkspaceFolder} → null (unsupported)", resolveEnvSubstitution("${containerWorkspaceFolder}") === null);
  ok("plain 'root' passes through", resolveEnvSubstitution("root") === "root");
  ok("empty string passes through", resolveEnvSubstitution("  ") === "");

  // remoteUser "${localEnv:USER}" — the exact broken value from this workspace
  const dc = { remoteUser: "${localEnv:USER}", containerUser: "bob" };
  ok("resolveUser resolves ${localEnv:USER} to host user", (await resolveUser("g1_ws", dc, "auto")) === process.env.USER);
  ok("resolveUser falls through unresolvable → containerUser", (await resolveUser("g1_ws", { remoteUser: "${localEnv:UNSET_VAR_XYZ}", containerUser: "bob" }, "auto")) === "bob");
  ok("resolveUser explicit config wins", (await resolveUser("g1_ws", dc, "root")) === "root");
}

// ===========================================================================
section("Unit: path mapping");
// ===========================================================================

{
  const { resolveWorkspaceFolder, toContainerPathFn } = ext;
  const root = WORKSPACE;
  const dc = { workspaceFolder: "${localWorkspaceFolder}" };
  ok("workspaceFolder ${localWorkspaceFolder} → root", resolveWorkspaceFolder(root, dc) === root);
  ok("workspaceFolder ${localWorkspaceFolder}/sub → root/sub", resolveWorkspaceFolder(root, { workspaceFolder: "${localWorkspaceFolder}/sub" }) === root + "/sub");
  ok("workspaceFolder ${containerWorkspaceFolder} → null (identity fallback)", resolveWorkspaceFolder(root, { workspaceFolder: "${containerWorkspaceFolder}" }) === null);
  ok("workspaceFolder override wins", resolveWorkspaceFolder(root, dc, "/ws") === "/ws");

  const identity = toContainerPathFn(root, null);
  ok("identity mapping (no workspaceFolder)", identity(root + "/docs/a.md") === root + "/docs/a.md");
  const mapped = toContainerPathFn(root, { workspaceFolder: "/ws" });
  ok("mapped: root → /ws", mapped(root) === "/ws");
  ok("mapped: root/docs → /ws/docs", mapped(root + "/docs") === "/ws/docs");
  ok("mapped: outside root passes through", mapped("/home/marc/other") === "/home/marc/other");
}

// ===========================================================================
section("Unit: env entries");
// ===========================================================================

{
  const { resolveEnvEntries } = ext;
  const dc = { remoteEnv: { VIA_LOCAL: "${localEnv:USER}", PLAIN: "value", MISSING: "${localEnv:UNSET_VAR_XYZ}", HOME: null } };
  const entries = resolveEnvEntries(dc, { OVERRIDE: "x" });
  const map = new Map(entries);
  ok("remoteEnv ${localEnv:USER} resolved", map.get("VIA_LOCAL") === process.env.USER);
  ok("remoteEnv plain kept", map.get("PLAIN") === "value");
  ok("remoteEnv unresolvable skipped", !map.has("MISSING"));
  ok("remoteEnv null copies from host", map.get("HOME") === process.env.HOME);
  ok("config env merged", map.get("OVERRIDE") === "x");
}

// ===========================================================================
section("Unit: noise filter");
// ===========================================================================

{
  const { JobControlNoiseFilter } = ext;
  const f = new JobControlNoiseFilter(true);
  const out = f.transform(Buffer.from("bash: cannot set terminal process group (-1): Inappropriate ioctl for device\nbash: no job control in this shell\nhello\nworld\n"));
  ok("strips both noise lines, keeps content", out.toString() === "hello\nworld\n");
  const g = new JobControlNoiseFilter(true);
  const partial = g.transform(Buffer.from("bash: no job control in this "));
  ok("partial noise line held back", partial.toString() === "");
  const rest = g.transform(Buffer.from("shell\nkeep me\n"));
  ok("completed noise line dropped", rest.toString() === "keep me\n");
  ok("flush after trailing partial noise is empty", g.flush().toString() === "");
  const h = new JobControlNoiseFilter(true);
  h.transform(Buffer.from("trailing "));
  ok("flush keeps trailing partial content", h.flush().toString() === "trailing ");
  ok("utf8 split across chunks (🚀)", (() => {
    const u = new JobControlNoiseFilter(true);
    const bytes = Buffer.from("x\n🚀"); // 0x78 0x0a f0 9f 9a 80
    const part1 = u.transform(bytes.subarray(0, 4)); // "x\n" + first 2 bytes of 🚀
    const part2 = u.transform(bytes.subarray(4));
    const tail = u.flush();
    return part1.toString() === "x\n" && part2.toString() === "" && tail.toString() === "🚀";
  })());
  const off = new JobControlNoiseFilter(false);
  const raw = off.transform(Buffer.from("bash: no job control in this shell\n"));
  ok("disabled filter passes everything", raw.toString() === "bash: no job control in this shell\n");
}

// ===========================================================================
section("Unit: timeout validation");
// ===========================================================================

{
  const { resolveTimeoutMs } = ext;
  ok("undefined → undefined", resolveTimeoutMs(undefined) === undefined);
  ok("seconds → ms", resolveTimeoutMs(5) === 5000);
  let threw = false;
  try { resolveTimeoutMs(0); } catch { threw = true; }
  ok("0 throws", threw);
  threw = false;
  try { resolveTimeoutMs(-1); } catch { threw = true; }
  ok("negative throws", threw);
  threw = false;
  try { resolveTimeoutMs(Number.NaN); } catch { threw = true; }
  ok("NaN throws", threw);
  threw = false;
  try { resolveTimeoutMs(1e12); } catch { threw = true; }
  ok("too large throws", threw);
}

// ===========================================================================
section("Integration: detection & routing (real docker)");
// ===========================================================================

{
  const { findContainerId, resolveRoute, DEFAULT_CONFIG, readDevcontainerJson, resolveUser } = ext;
  const id = await findContainerId(WORKSPACE);
  ok("findContainerId finds running container", typeof id === "string" && id.length > 0, id);
  const explicit = await findContainerId(WORKSPACE, "g1_ws");
  ok("findContainerId explicit name", typeof explicit === "string" && explicit.length > 0, explicit);
  const missing = await findContainerId(WORKSPACE, "dcb-definitely-not-running");
  ok("findContainerId explicit missing → trusted passthrough", missing === "dcb-definitely-not-running");

  const mode = await resolveRoute(WORKSPACE, { ...DEFAULT_CONFIG, enabled: true });
  ok("resolveRoute → routed", mode.kind === "routed", mode.kind);
  if (mode.kind === "routed") {
    ok("resolved user is marc (from ${localEnv:USER})", mode.resolved.user === "marc", mode.resolved.user);
    ok("container id sane", mode.resolved.containerId.length > 0);
    ok("identity path mapping", mode.resolved.toContainerPath(WORKSPACE) === WORKSPACE);
    ok("interactive shell", mode.resolved.interactive === true);
  }

  const dc = readDevcontainerJson(WORKSPACE);
  ok("devcontainer.json read", dc !== null);
  const user = await resolveUser("g1_ws", dc, "auto");
  ok("resolveUser real devcontainer.json → marc", user === "marc", user);

  const inert = await resolveRoute("/tmp", { ...DEFAULT_CONFIG, enabled: true });
  ok("resolveRoute outside workspace → inert", inert.kind === "inert");
}

// ===========================================================================
section("Integration: docker exec operations");
// ===========================================================================

{
  const { createDockerBashOperations, resolveRoute, DEFAULT_CONFIG } = ext;
  const mode = await resolveRoute(WORKSPACE, { ...DEFAULT_CONFIG, enabled: true });
  if (mode.kind !== "routed") {
    ok("SKIPPED (no routed container)", false, "container not running");
  } else {
    const ops = createDockerBashOperations(mode.resolved);

    async function exec(cmd, cwd = WORKSPACE, opts = {}) {
      const chunks = [];
      const result = await ops.exec(cmd, cwd, { onData: (b) => chunks.push(b.toString()), ...opts });
      return { ...result, output: chunks.join("") };
    }

    // basic
    const basic = await exec("whoami; echo hello-container; pwd");
    ok("basic command exit 0", basic.exitCode === 0, basic);
    ok("runs as marc", /^marc$/m.test(basic.output), basic.output);
    ok("output contains hello", basic.output.includes("hello-container"));
    ok("no job-control noise", !NOISE.test(basic.output), basic.output);

    // cwd mapping into a subdir
    const sub = await exec("pwd", join(WORKSPACE, "docs"));
    ok("cwd mapped to container subdir", sub.output.trim() === join(WORKSPACE, "docs"), sub);

    // exit code
    const bad = await exec("exit 7");
    ok("exit code 7 propagated", bad.exitCode === 7, bad);

    // special characters
    const special = await exec('printf "%s\\n" "sp ace" "ünïcode-🚀" "\\$HOME-is-\\$HOME" "back\\`tick"');
    ok("special chars pass through", special.output.includes("sp ace") && special.output.includes("ünïcode-🚀") && special.output.includes("back`tick"), special.output);

    // multiline command
    const multi = await exec("echo line1\necho line2\necho line3");
    ok("multiline command", multi.output.includes("line1") && multi.output.includes("line2") && multi.output.includes("line3"), multi);

    // very long command (~60KB single argv)
    const longCmd = `printf '%s' '${"A".repeat(60000)}' | wc -c`;
    const long = await exec(longCmd);
    ok("60KB command arg works", long.exitCode === 0 && long.output.trim() === "60000", long.output.slice(0, 80));

    // large output (1MB)
    const big = await exec("head -c 1048576 /dev/zero | tr '\\0' 'x' | wc -c");
    ok("1MB output streamed", big.exitCode === 0 && big.output.trim() === "1048576", big.output.slice(0, 80));

    // stdin independence: `cat` must not hang
    const started = Date.now();
    const cat = await exec("cat");
    const catMs = Date.now() - started;
    ok("cat with no stdin returns immediately (<3s)", cat.exitCode === 0 && catMs < 3000, { ms: catMs, code: cat.exitCode });

    // background jobs
    const bg = await exec("(sleep 2 &); echo bg-started");
    ok("background job starts, shell not blocked", bg.exitCode === 0 && bg.output.includes("bg-started"), bg);

    // nonexistent container cwd → clear error, not a hang
    const badcwd = await exec("pwd", join(WORKSPACE, "definitely-not-a-dir-xyz"));
    ok("nonexistent cwd errors clearly", badcwd.exitCode !== 0 && /chdir|cwd|no such file|failed/i.test(badcwd.output), badcwd);

    // sudo
    const sudo = await exec("sudo -n true");
    ok("sudo -n works", sudo.exitCode === 0, sudo);

    // interactive shell sources ~/.bashrc (ROS toolchain)
    const ros = await exec("printenv ROS_DISTRO || echo no-ros");
    console.log(`  info: ROS_DISTRO=${ros.output.trim()}`);

    // env entries are not injected when not configured
    const env = await exec("env | grep -c '^DCB_' || true");
    ok("no phantom env injected", env.output.trim() === "0", env);
  }
}

// ===========================================================================
section("Integration: full tool (createBashTool) semantics");
// ===========================================================================

{
  const { createDockerBashOperations, resolveRoute, DEFAULT_CONFIG } = ext;
  const { createBashTool } = piPkg;
  const mode = await resolveRoute(WORKSPACE, { ...DEFAULT_CONFIG, enabled: true });
  if (mode.kind !== "routed") {
    ok("SKIPPED (no routed container)", false, "container not running");
  } else {
    const tool = createBashTool(WORKSPACE, {
      operations: createDockerBashOperations(mode.resolved),
      exposeSessionEnvironment: false,
    });

    // normal execution through the real pi tool path
    const r = await tool.execute("t1", { command: "echo tool-path-ok; pwd" }, undefined, undefined, undefined);
    const text = r.content.map((c) => c.text).join("");
    ok("tool executes, content streamed", text.includes("tool-path-ok") && text.includes(WORKSPACE), text.slice(0, 120));

    // non-zero exit → pi-style error
    let err = null;
    try { await tool.execute("t2", { command: "echo before; exit 3" }, undefined, undefined, undefined); } catch (e) { err = e; }
    ok("exit 3 → 'Command exited with code 3'", err instanceof Error && /Command exited with code 3/.test(err.message) && err.message.includes("before"), err?.message);

    // truncation: 100k lines → last-2000-lines behavior + temp file
    const big = await tool.execute("t3", { command: "seq 1 100000" }, undefined, undefined, undefined);
    const bigText = big.content.map((c) => c.text).join("");
    ok("huge output truncated", bigText.includes("[Showing lines"), bigText.slice(-200));
    ok("truncation details present", big.details?.truncation?.truncated === true, big.details);
    ok("full output saved to temp file", typeof big.details?.fullOutputPath === "string" && existsSync(big.details.fullOutputPath), big.details);
    if (typeof big.details?.fullOutputPath === "string" && existsSync(big.details.fullOutputPath)) {
      const lines = readFileSync(big.details.fullOutputPath, "utf8").trim().split("\n");
      ok("temp file has all 100000 lines", lines.length === 100000 && lines[99999] === "100000", lines.length);
    }
  }
}

// ===========================================================================
section("Integration: timeout");
// ===========================================================================

{
  const { createDockerBashOperations, resolveRoute, DEFAULT_CONFIG } = ext;
  const { createBashTool } = piPkg;
  const mode = await resolveRoute(WORKSPACE, { ...DEFAULT_CONFIG, enabled: true });
  if (mode.kind !== "routed") {
    ok("SKIPPED (no routed container)", false, "container not running");
  } else {
    const tool = createBashTool(WORKSPACE, {
      operations: createDockerBashOperations(mode.resolved),
      exposeSessionEnvironment: false,
    });
    const t0 = Date.now();
    let err = null;
    try {
      await tool.execute("t4", { command: "echo started; setsid sleep 99 & sleep 60; echo never", timeout: 2 }, undefined, undefined, undefined);
    } catch (e) { err = e; }
    const elapsed = Date.now() - t0;
    ok("timeout → 'Command timed out after 2 seconds'", err instanceof Error && /Command timed out after 2 seconds/.test(err.message), err?.message);
    ok("timeout fires promptly (<15s)", elapsed < 15000, `${elapsed}ms`);
    ok("partial output included", err?.message?.includes("started"), err?.message);

    // the in-container process must be GONE (client kill alone leaves it)
    await new Promise((r) => setTimeout(r, 1500));
    const leftovers = inContainer("pgrep -f 'sleep 6[0]' || true");
    ok("no leftover sleep 60 in container", leftovers === "", leftovers);

    // detached setsid process from the timed-out command must be gone too
    const leftovers2 = inContainer("pgrep -f 'setsid sleep 9[9]' || true");
    ok("no leftover detached setsid process", leftovers2 === "", leftovers2);
  }
}

// ===========================================================================
section("Integration: abort");
// ===========================================================================

{
  const { createDockerBashOperations, resolveRoute, DEFAULT_CONFIG } = ext;
  const { createBashTool } = piPkg;
  const mode = await resolveRoute(WORKSPACE, { ...DEFAULT_CONFIG, enabled: true });
  if (mode.kind !== "routed") {
    ok("SKIPPED (no routed container)", false, "container not running");
  } else {
    const tool = createBashTool(WORKSPACE, {
      operations: createDockerBashOperations(mode.resolved),
      exposeSessionEnvironment: false,
    });
    const ac = new AbortController();
    setTimeout(() => ac.abort(), 1000);
    let err = null;
    try {
      await tool.execute("t5", { command: "echo about-to-abort; sleep 60" }, ac.signal, undefined, undefined);
    } catch (e) { err = e; }
    ok("abort → 'Command aborted'", err instanceof Error && /Command aborted/.test(err.message), err?.message);
    await new Promise((r) => setTimeout(r, 1500));
    const leftovers = inContainer("pgrep -f 'sleep 6[0]' || true");
    ok("no leftover sleep 60 after abort", leftovers === "", leftovers);
  }
}

// ===========================================================================
section("Integration: concurrency (16 parallel execs)");
// ===========================================================================

{
  const { createDockerBashOperations, resolveRoute, DEFAULT_CONFIG } = ext;
  const mode = await resolveRoute(WORKSPACE, { ...DEFAULT_CONFIG, enabled: true });
  if (mode.kind !== "routed") {
    ok("SKIPPED (no routed container)", false, "container not running");
  } else {
    const ops = createDockerBashOperations(mode.resolved);
    const results = await Promise.all(
      Array.from({ length: 16 }, (_, i) =>
        ops.exec(`echo start-${i}; sleep $((RANDOM % 2)); echo end-${i}`, WORKSPACE, {
          onData: () => {},
        }).then((r) => ({ i, ...r })),
      ),
    );
    const allOk = results.every((r) => r.exitCode === 0);
    ok("16 parallel execs all exit 0", allOk, results.filter((r) => r.exitCode !== 0).map((r) => r.i));
  }
}

// ===========================================================================
section("Unit: extension factory (mock pi API)");
// ===========================================================================

{
  const registrations = { flags: [], tools: [], commands: [], events: {} };
  const mockPi = {
    registerFlag: (n, d) => registrations.flags.push([n, d]),
    registerTool: (t) => registrations.tools.push(t),
    registerCommand: (n, d) => registrations.commands.push([n, d]),
    on: (e, h) => (registrations.events[e] = h),
    getFlag: () => false,
  };
  ext.default(mockPi);
  ok("factory runs without throwing", true);
  ok("registers bash tool", registrations.tools.some((t) => t.name === "bash" && t.label === "bash (devcontainer)"));
  ok("registers /devcontainer-bash command", registrations.commands.some(([n]) => n === "devcontainer-bash"));
  ok("registers --no-devcontainer-bash flag", registrations.flags.some(([n]) => n === "no-devcontainer-bash"));
  ok("registers user_bash handler", typeof registrations.events.user_bash === "function");
}

// ===========================================================================
section("Cleanliness");
// ===========================================================================

{
  const pgids = inContainer("ls /tmp/pi-dcb-*.pgid 2>/dev/null || true");
  ok("no leftover pgid files in container", pgids === "", pgids);
  const sleeps = inContainer("pgrep -c -f 'sleep 6[0]' || true");
  ok("no stray sleep processes", sleeps === "" || sleeps === "0", sleeps);
}

// ===========================================================================
console.log(`\n${passed} passed, ${failed} failed`);
if (failed > 0) {
  console.log("Failures:", failures.join(", "));
  process.exit(1);
}
