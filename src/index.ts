#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { runCapture } from "./capture.js";
import {
  captureDeskViewJsonSchema,
  captureOnGestureJsonSchema,
  captureOnStableJsonSchema,
} from "./schemas.js";
import type { ServerResult } from "@modelcontextprotocol/sdk/types.js";
import type { ToolName } from "./types.js";

const server = new Server(
  { name: "deskview-mcp", version: "1.2.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "capture_desk_view",
      description:
        "Capture a single frame from the Desk View camera right now. Returns a base64 PNG image content block.",
      inputSchema: captureDeskViewJsonSchema,
    },
    {
      name: "capture_on_stable",
      description:
        "Wait until the scene stabilizes (motion stops for stability_duration_ms continuous milliseconds), then capture one frame. Zero token cost during the wait.",
      inputSchema: captureOnStableJsonSchema,
    },
    {
      name: "capture_on_gesture",
      description:
        "Wait until the specified hand gesture is detected and held for hold_duration_ms, then capture one frame. Supported gestures: thumbs_up, peace, ok_sign, fist, open_palm.",
      inputSchema: captureOnGestureJsonSchema,
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  return (await runCapture(name as ToolName, args ?? {})) as unknown as ServerResult;
});

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write("deskview-mcp server connected\n");
