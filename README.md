# Deskview MCP

A Claude Desktop Extension that gives Claude direct access to the iPhone Continuity Camera Desk View feed for capturing physical workspace frames.

## What it does

Three MCP tools, all running fully on-device:

- **`capture_desk_view`** -- Capture one frame from the Desk View camera right now.
- **`capture_on_stable`** -- Wait until the scene stops moving for a configurable duration, then capture.
- **`capture_on_gesture`** -- Wait until a specific hand gesture is detected and held, then capture.

All motion detection and gesture recognition run natively on-device using AVFoundation and the Vision framework. No network calls are made.

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon (arm64). Intel is not supported in v1.
- iPhone running iOS 16 or later, signed into the same iCloud account as the Mac.
- Bluetooth and Wi-Fi enabled on both devices.
- Desk View enabled in Mac Control Center (open Control Center, look for the Desk View toggle in the Video Effects section).
- iPhone mounted overhead (a Belkin MagSafe Continuity Camera mount or equivalent works well).

## Install

1. Download the `.mcpb` bundle from the [Releases](https://github.com/alexey-max-fedorov/deskview-mcp/releases) page.
2. Open Claude Desktop and go to **Settings**.
3. Click **Extensions**.
4. Click **Advanced settings**, then **Extension Developer**.
5. Click **Install Extension...** and select the `.mcpb` file.
6. Confirm the installation prompt.

The first time you invoke any tool, macOS will show a camera permission prompt. If you accidentally deny it, go to **System Settings > Privacy and Security > Camera** and enable Claude Desktop. There is no programmatic way to re-trigger the prompt.

## Tools

### `capture_desk_view`

Captures a single frame immediately. Takes no inputs.

**Output:** One image content block (JPEG) plus a short text block with capture metadata.

**Use when:** You want an instant snapshot of what is on the desk right now.

---

### `capture_on_stable`

Waits until the scene has been still for `stability_duration_ms` milliseconds, then captures one frame.

| Parameter | Type | Range | Default | Description |
|---|---|---|---|---|
| `stability_duration_ms` | number | 500 -- 30000 | `3000` | How long (ms) the scene must remain still before capturing. |
| `timeout_ms` | number | 1000 -- 1800000 | `300000` | Maximum total wait time (ms). If reached without stabilization, returns the last frame with a timeout note. |
| `sensitivity` | string | `low`, `medium`, `high` | `"medium"` | Motion detector sensitivity. `low` tolerates up to 5% pixel change, `medium` 2%, `high` 0.5%. |

**Output:** One image content block (JPEG) plus a short text block with capture metadata.

**Use when:** You want a clean, blur-free shot of an object placed on the desk, without having to time the capture manually.

---

### `capture_on_gesture`

Waits until a specific hand gesture is detected and held continuously for `hold_duration_ms` milliseconds, then captures one frame.

| Parameter | Type | Range | Default | Description |
|---|---|---|---|---|
| `gesture` | string (required) | `thumbs_up`, `peace`, `ok_sign`, `fist`, `open_palm` | -- | Which hand gesture to wait for. |
| `hold_duration_ms` | number | 100 -- 5000 | `500` | How long (ms) the gesture must be held to count. Prevents false positives from brief flashes. |
| `timeout_ms` | number | 1000 -- 1800000 | `300000` | Maximum total wait time (ms). Returns an error text block if the gesture is not detected in time. |

**Output:** One image content block (JPEG) plus a short text block with capture metadata.

**Use when:** You want the user to control the exact moment of capture without Claude needing to poll or re-invoke the tool.

## Build from source

Requires **pnpm 8+** and **Swift 5.9+**.

```bash
pnpm install       # install Node dependencies
pnpm build         # compile Swift binary (arm64) and transpile TypeScript
pnpm test          # run the Vitest test suite
pnpm package       # build + bundle into a .mcpb file
```

`pnpm package` calls `pnpm build` first, then runs `scripts/package.sh`, which temporarily moves dev `node_modules` aside to produce a flat, prod-only bundle, then restores them.

## How it works

The MCP server is a Node.js process (TypeScript, stdio transport) that validates tool inputs with Zod and then spawns a compiled Swift CLI binary. The Swift binary owns AVFoundation, Vision, and CoreImage: it opens the Desk View camera, runs motion analysis or gesture detection in a native loop, captures a JPEG frame (quality 0.85, max long edge 1280px), and writes a JSON result to stdout. Because the wait loop runs inside the Swift process, Claude receives zero intermediate frames and incurs zero token cost during the wait. The binary exits once a frame is ready, and the Node server parses stdout and returns the image content block to Claude.

## Troubleshooting

**"No Desk View camera found"**
Confirm the iPhone is mounted, signed into the same iCloud account as the Mac, and that Desk View is enabled in Mac Control Center. Toggling Bluetooth off and on can help if the camera is not appearing.

**"Camera permission denied"**
Go to **System Settings > Privacy and Security > Camera** and enable Claude Desktop. There is no programmatic re-prompt once permission is denied.

**Tool returns text but no image**
Open **Settings > Extensions**, find Deskview MCP, and open the Extension Developer logs panel. Look for stderr output from the Swift binary -- it will include a descriptive error if AVFoundation failed to initialize or capture.

**Bundle install fails with "Server transport closed"**
This almost always means the bundle was packed with dev `node_modules` instead of a flat prod layout. Make sure you used `pnpm package` (which calls `scripts/package.sh`) rather than packing the source directory directly.

## Privacy

All detection runs on-device. Deskview MCP makes no network calls and collects no telemetry. Captured frames are held in the local extension process and are returned as JPEG content blocks to Claude only when the user explicitly invokes a tool.

## License

Copyright (c) 2026 Alexey Fedorov. All rights reserved.

Released under the [PolyForm Noncommercial License 1.0.0](https://polyformproject.org/licenses/noncommercial/1.0.0/) — free for personal, research, educational, and other noncommercial use. For commercial use, contact alexey.max.fedorov@gmail.com.

The software is provided "as is", without warranty of any kind. See `LICENSE` for the full disclaimer of liability.
