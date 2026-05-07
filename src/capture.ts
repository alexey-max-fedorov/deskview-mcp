import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { z } from "zod";
import {
  captureDeskViewInput,
  captureOnGestureInput,
  captureOnStableInput,
} from "./schemas.js";
import type {
  McpToolResponse,
  SwiftResult,
  ToolName,
} from "./types.js";

interface RunOpts {
  binPath?: string;
}

const SAFETY_BUDGET_MS = 5_000;

export async function runCapture(
  name: ToolName,
  args: Record<string, unknown>,
  opts: RunOpts = {}
): Promise<McpToolResponse> {
  const binPath = opts.binPath ?? process.env.DESKVIEW_BIN;
  if (!binPath) {
    return errorResponse(
      "Bundle is misconfigured: DESKVIEW_BIN env var is not set. Reinstall the extension."
    );
  }
  if (!existsSync(binPath)) {
    return errorResponse(
      `Deskview capture binary not found at ${binPath}. The extension bundle may be corrupted; reinstall it.`
    );
  }

  let cliArgs: string[];
  let upperBoundMs: number;
  try {
    const parsed = parseArgs(name, args);
    cliArgs = parsed.cliArgs;
    upperBoundMs = parsed.upperBoundMs;
  } catch (err) {
    if (err instanceof z.ZodError) {
      return errorResponse(
        `Invalid input for ${name}: ${err.issues.map((i) => i.message).join("; ")}`
      );
    }
    return errorResponse(
      `Unknown tool: ${String(name)}. Expected one of capture_desk_view, capture_on_stable, capture_on_gesture.`
    );
  }

  const swift = await spawnBinary(binPath, cliArgs, upperBoundMs + SAFETY_BUDGET_MS);
  if (!swift.ok) {
    return errorResponse(
      `Deskview binary failed (exit ${swift.code}): ${swift.stderr.slice(0, 500) || "no stderr"}`
    );
  }

  let parsed: SwiftResult;
  try {
    parsed = JSON.parse(swift.stdout) as SwiftResult;
  } catch {
    return errorResponse(
      `Deskview binary returned invalid JSON. stdout (truncated): ${swift.stdout.slice(0, 200)}`
    );
  }

  return mapResult(parsed);
}

function parseArgs(
  name: ToolName | string,
  args: Record<string, unknown>
): { cliArgs: string[]; upperBoundMs: number } {
  switch (name) {
    case "capture_desk_view": {
      captureDeskViewInput.parse(args);
      return { cliArgs: ["snapshot"], upperBoundMs: 5_000 };
    }
    case "capture_on_stable": {
      const v = captureOnStableInput.parse(args);
      return {
        cliArgs: [
          "stable",
          "--duration",
          String(v.stability_duration_ms),
          "--timeout",
          String(v.timeout_ms),
          "--sensitivity",
          v.sensitivity,
        ],
        upperBoundMs: v.timeout_ms,
      };
    }
    case "capture_on_gesture": {
      const v = captureOnGestureInput.parse(args);
      return {
        cliArgs: [
          "gesture",
          "--type",
          v.gesture,
          "--hold",
          String(v.hold_duration_ms),
          "--timeout",
          String(v.timeout_ms),
        ],
        upperBoundMs: v.timeout_ms,
      };
    }
    default:
      throw new Error(`unknown tool: ${name}`);
  }
}

interface SpawnResult {
  ok: boolean;
  code: number | null;
  stdout: string;
  stderr: string;
}

function spawnBinary(
  binPath: string,
  args: string[],
  hardKillMs: number
): Promise<SpawnResult> {
  return new Promise((resolve) => {
    const child = spawn(binPath, args, { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";

    const killer = setTimeout(() => {
      try { child.kill("SIGKILL"); } catch { /* ignored */ }
    }, hardKillMs);

    child.stdout.on("data", (chunk: Buffer) => { stdout += chunk.toString("utf8"); });
    child.stderr.on("data", (chunk: Buffer) => {
      const s = chunk.toString("utf8");
      stderr += s;
      process.stderr.write(s);
    });

    child.on("error", (err) => {
      clearTimeout(killer);
      resolve({ ok: false, code: null, stdout, stderr: stderr || err.message });
    });

    child.on("close", (code) => {
      clearTimeout(killer);
      resolve({ ok: code === 0, code, stdout, stderr });
    });
  });
}

function mapResult(r: SwiftResult): McpToolResponse {
  if (r.status === "error") {
    return errorResponse(r.error_message ?? "Capture failed.");
  }

  if (!r.image_base64 || !r.metadata) {
    if (r.status === "timeout") {
      return errorResponse(
        r.error_message ??
          "Operation timed out before a frame could be captured."
      );
    }
    return errorResponse(
      "Deskview returned a success status but no image data. The binary may be malfunctioning."
    );
  }

  const text =
    r.status === "timeout"
      ? `Timeout reached after ${r.metadata.wait_duration_ms}ms. Returning last captured frame.`
      : `Captured Desk View frame at ${r.metadata.captured_at}. Resolution: ${r.metadata.width}x${r.metadata.height}.`;

  return {
    content: [
      { type: "image", data: r.image_base64, mimeType: "image/png" },
      { type: "text", text },
    ],
  };
}

function errorResponse(text: string): McpToolResponse {
  return { content: [{ type: "text", text }], isError: true };
}
