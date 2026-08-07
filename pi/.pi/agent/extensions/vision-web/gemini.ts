/**
 * Minimal Gemini REST client. Direct HTTP — no pi provider registry required.
 *
 * Vision: POST /v1beta/models/{model}:generateContent with inline base64 data.
 */
export interface ImageInput {
  data: string; // base64
  mimeType: string;
}

const API_BASE = "https://generativelanguage.googleapis.com/v1beta";
const DEFAULT_TIMEOUT_MS = 120_000;

export function withTimeout(signal: AbortSignal | undefined, timeoutMs: number): AbortSignal {
  const timeout = AbortSignal.timeout(timeoutMs);
  if (signal && typeof AbortSignal.any === "function") return AbortSignal.any([signal, timeout]);
  return signal ?? timeout;
}

/** Never leak the API key in errors or logs. */
export function redact(text: string, secret: string | undefined): string {
  return secret && secret.length > 4 ? text.split(secret).join("[redacted]") : text;
}

export interface GenerateOptions {
  apiKey: string;
  model: string;
  signal?: AbortSignal;
  timeoutMs?: number;
}

async function generateContent(parts: unknown[], opts: GenerateOptions): Promise<string> {
  const url = `${API_BASE}/models/${opts.model}:generateContent`;
  const body = { contents: [{ role: "user", parts }] };
  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-goog-api-key": opts.apiKey },
      body: JSON.stringify(body),
      signal: withTimeout(opts.signal, opts.timeoutMs ?? DEFAULT_TIMEOUT_MS),
    });
  } catch (err) {
    throw new Error(`Gemini API request failed: ${redact(err instanceof Error ? err.message : String(err), opts.apiKey)}`);
  }
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(`Gemini API error ${response.status}: ${redact(raw, opts.apiKey).slice(0, 300)}`);
  }
  let data: any;
  try {
    data = JSON.parse(raw);
  } catch {
    throw new Error("Gemini API returned invalid JSON");
  }
  const partsOut = data?.candidates?.[0]?.content?.parts;
  const text = Array.isArray(partsOut)
    ? partsOut.map((p: any) => (typeof p?.text === "string" ? p.text : "")).join("\n").trim()
    : "";
  if (!text) {
    const blocked = data?.promptFeedback?.blockReason;
    throw new Error(blocked ? `Gemini API blocked the request: ${blocked}` : "Gemini API returned an empty response");
  }
  return text;
}

export function imagePart(img: ImageInput): unknown {
  return { inlineData: { mimeType: img.mimeType, data: img.data } };
}

export function fileDataPart(fileUri: string, mimeType?: string): unknown {
  const part: Record<string, unknown> = { fileData: { fileUri } };
  if (mimeType) (part.fileData as Record<string, unknown>).mimeType = mimeType;
  return part;
}

export function pdfPart(data: Buffer): unknown {
  return { inlineData: { mimeType: "application/pdf", data: data.toString("base64") } };
}

export function textPart(text: string): unknown {
  return { text };
}

/** Generate content from raw parts (images, fileData, PDFs, text). */
export async function generateParts(parts: unknown[], opts: GenerateOptions): Promise<string> {
  return generateContent(parts, opts);
}

function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

export interface DescribeOptions extends GenerateOptions {
  /** Cap on the returned description in lines (0 = unbounded). */
  maxDescriptionLines?: number;
}

/**
 * Describe images in batches (batchSize images per request). Returns one
 * string per input image, in order.
 */
export async function describeImages(images: ImageInput[], userPrompt: string, opts: DescribeOptions): Promise<string[]> {
  const batches = chunk(images, Math.max(1, Math.floor(opts.batchSize ?? 1)));
  const descriptions: string[] = [];
  let index = 0;
  for (const batch of batches) {
    const prompt =
      batch.length === 1
        ? userPrompt || "Describe this image."
        : `${userPrompt || "Describe these images."}\n\nDescribe each of the ${batch.length} images below exhaustively, in order. For image k (1 through ${batch.length}), emit exactly:\n\n<<<IMAGE k>>>\n<your exhaustive description>\n<<<END>>>\n\n`;
    const parts: unknown[] = batch.map(imagePart);
    parts.push(textPart(prompt));
    const text = await generateContent(parts, opts);
    const split = batch.length > 1 ? splitSections(text, batch.length) : null;
    for (let i = 0; i < batch.length; i++) {
      const section = split ? split[i] : text;
      const trimmed = (section ?? "").trim();
      descriptions.push(opts.maxDescriptionLines && opts.maxDescriptionLines > 0 ? truncateLines(trimmed, opts.maxDescriptionLines) : trimmed);
      index++;
    }
  }
  return descriptions;
}

/** Parse "<<<IMAGE k>>> ... <<<END>>>" sections; returns null if parsing failed. */
function splitSections(text: string, count: number): (string | null)[] | null {
  const sections: (string | null)[] = new Array(count).fill(null);
  const re = /<<<IMAGE\s+(\d+)>>>\s*([\s\S]*?)<<<END>>>/g;
  let match: RegExpExecArray | null;
  let found = 0;
  while ((match = re.exec(text)) !== null) {
    const k = Number(match[1]);
    if (k >= 1 && k <= count) {
      sections[k - 1] = match[2];
      found++;
    }
  }
  if (found === 0) return null;
  return sections;
}

function truncateLines(text: string, maxLines: number): string {
  const lines = text.split("\n");
  if (lines.length <= maxLines) return text;
  const hidden = lines.length - maxLines;
  return `${lines.slice(0, maxLines).join("\n")}\n... (${hidden} more lines)`;
}
