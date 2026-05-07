import { describe, it, expect } from "vitest";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { runCapture } from "../capture.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixture = (name: string) => path.join(__dirname, "fixtures", name);

describe("runCapture", () => {
  it("returns image + text content blocks on success", async () => {
    const result = await runCapture("capture_desk_view", {}, {
      binPath: fixture("stub-success.sh"),
    });
    expect(result.isError).toBeFalsy();
    expect(result.content).toHaveLength(2);
    expect(result.content[0]).toMatchObject({ type: "image", mimeType: "image/png" });
    expect((result.content[0] as { data: string }).data.length).toBeGreaterThan(20);
    expect(result.content[1]).toMatchObject({ type: "text" });
    expect((result.content[1] as { text: string }).text).toContain("1920x1440");
  });

  it("returns image + timeout note on timeout", async () => {
    const result = await runCapture("capture_on_stable", { timeout_ms: 1000 }, {
      binPath: fixture("stub-timeout.sh"),
    });
    expect(result.isError).toBeFalsy();
    expect(result.content[0]).toMatchObject({ type: "image" });
    expect((result.content[1] as { text: string }).text.toLowerCase()).toContain("timeout");
  });

  it("returns isError text on no_device", async () => {
    const result = await runCapture("capture_desk_view", {}, {
      binPath: fixture("stub-error.sh"),
    });
    expect(result.isError).toBe(true);
    expect(result.content).toHaveLength(1);
    expect((result.content[0] as { text: string }).text).toContain("Desk View");
  });

  it("surfaces a clear error if the binary crashes with non-JSON output", async () => {
    const result = await runCapture("capture_desk_view", {}, {
      binPath: fixture("stub-crash.sh"),
    });
    expect(result.isError).toBe(true);
    expect((result.content[0] as { text: string }).text.toLowerCase()).toContain("binary");
  });

  it("returns a clear error if the binary path does not exist", async () => {
    const result = await runCapture("capture_desk_view", {}, {
      binPath: "/nonexistent/deskview-capture",
    });
    expect(result.isError).toBe(true);
    expect((result.content[0] as { text: string }).text.toLowerCase()).toContain("not found");
  });

  it("rejects unknown tool names", async () => {
    const result = await runCapture("not_a_tool" as never, {}, {
      binPath: fixture("stub-success.sh"),
    });
    expect(result.isError).toBe(true);
    expect((result.content[0] as { text: string }).text.toLowerCase()).toContain("unknown");
  });

  it("validates input schema before spawning", async () => {
    const result = await runCapture(
      "capture_on_gesture",
      { gesture: "not_a_gesture" } as never,
      { binPath: fixture("stub-success.sh") }
    );
    expect(result.isError).toBe(true);
    expect((result.content[0] as { text: string }).text.toLowerCase()).toMatch(/gesture|invalid/);
  });
});
