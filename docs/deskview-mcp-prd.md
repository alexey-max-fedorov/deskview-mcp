# Deskview MCP — Product Requirements Document

**Version:** 1.0
**Format:** MCP Bundle (`.mcpb`) following manifest spec v0.3
**Target client:** Claude Desktop on macOS (Apple Silicon)
**Owner:** Alexey Fedorov

---

## 1. Overview

### What this is

A Claude Desktop Extension distributed as an `.mcpb` bundle that gives Claude direct access to the iPhone Continuity Camera Desk View feed via Apple's `AVFoundation` framework. The extension exposes three MCP tools for capturing single frames of the user's physical workspace: instant capture, capture-when-stable, and capture-on-gesture.

### Why this exists

Existing screen-capture MCPs grab the screen. This one grabs the **desk** via the iPhone overhead camera. Use cases include grading worksheets when finished, verifying physical builds and prototypes, ambient agentic context in long-running Claude Code sessions, and providing physical-world context for Claude that screen-only tools cannot.

### Architecture summary

```
Claude Desktop (MCP host)
  └── Spawns via stdio transport (per manifest mcp_config)
      └── Node.js MCP server (server/index.js)
          - Registers 3 tools with @modelcontextprotocol/sdk
          - On tool call: child_process.spawn(swift binary)
          - Parses JSON from binary stdout
          - Returns MCP content blocks (image + text)
          └── Swift CLI binary (bin/deskview-capture, arm64)
              - AVFoundation: discover Desk View AVCaptureDevice
              - Vision framework: hand pose classification
              - CoreImage: pixel diff for stability detection
              - Outputs single JSON object to stdout, exits
```

The Node.js layer is a thin wrapper. All real camera work happens in the Swift binary because `AVFoundation` and `Vision` are not accessible from Node. The MCP server's job is protocol translation and process management.

### Tools exposed

| Tool name | Behavior | Cost during wait |
|---|---|---|
| `capture_desk_view` | Grab one frame immediately | None |
| `capture_on_stable` | Wait until motion stops for N seconds, then grab | Zero token cost (native CoreImage diff) |
| `capture_on_gesture` | Wait until specified hand gesture is detected, then grab | Zero token cost (native Vision framework) |

---

## 2. Goals and Non-Goals

### Goals (v1)

- Single double-click install via `.mcpb` bundle
- Native macOS camera permission flow on first run
- Sub-second capture latency for `capture_desk_view` happy path
- Zero per-frame token cost during wait operations
- Graceful fallback to `companionDeskViewCamera` if dedicated Desk View device not discoverable
- Self-contained bundle: ships compiled arm64 binary, no Swift runtime install needed by user
- Clear error surfaces when permissions denied or no iPhone connected

### Non-Goals (v1)

- Intel Mac support (arm64 only, M-series target)
- Burst capture or video streaming (single snapshot per call only)
- Drawn shape detection (stars, checkmarks, etc.), v2 candidate
- Custom user-trained gestures
- Region-of-interest cropping
- Per-frame Claude vision API calls during wait (would defeat the cost design)
- Cross-platform (Desk View is Apple-only by definition)

---

## 3. Project Structure

```
deskview-mcp/
├── manifest.json              # MCPB v0.3 manifest
├── package.json               # Node MCP server package definition
├── pnpm-lock.yaml             # pnpm lockfile (REQUIRED, never npm)
├── tsconfig.json              # TypeScript config
├── .mcpbignore                # Files to exclude from .mcpb pack
├── .gitignore
├── README.md
├── icon.png                   # 256x256 PNG icon for the extension
│
├── src/                       # TypeScript source (compiled to server/)
│   ├── index.ts               # MCP server entry, tool registration
│   ├── capture.ts             # Spawns Swift binary, parses stdout JSON
│   └── types.ts               # Shared types
│
├── server/                    # Compiled JS (mcp_config.entry_point)
│   └── index.js               # Built from src/ via tsc
│
├── swift/                     # Swift source (not shipped in bundle)
│   ├── Package.swift
│   ├── Sources/
│   │   └── DeskviewCapture/
│   │       ├── main.swift              # CLI entry, ArgumentParser
│   │       ├── DeskViewSession.swift   # AVCaptureSession setup + device discovery
│   │       ├── StableDetector.swift    # Frame diff motion detection loop
│   │       ├── GestureDetector.swift   # VNDetectHumanHandPoseRequest + classifier
│   │       └── ImageEncoder.swift      # CMSampleBuffer to PNG to base64
│   └── build.sh               # Compiles to ../bin/deskview-capture
│
├── bin/                       # Compiled binary (shipped in bundle)
│   └── deskview-capture       # arm64 macOS executable
│
└── node_modules/              # Production deps only (shipped in bundle)
```

### Package management rules

**pnpm only. Never npm. Never yarn.** This is non-negotiable for this project.

| Action | Command |
|---|---|
| Install all deps | `pnpm install` |
| Add a runtime dep | `pnpm add <pkg>` |
| Add a dev dep | `pnpm add -D <pkg>` |
| Run a script | `pnpm <script>` |
| Run an npx-style command | `pnpm dlx <cmd>` |
| Lockfile (committed) | `pnpm-lock.yaml` |

If any AI tool, script, or contributor tries to use `npm` or `yarn`, stop and fix it. Mixed lockfiles cause real bugs.

---

## 4. Manifest Specification

The manifest follows MCPB spec **version 0.3** (current as of Dec 2025).

### `manifest.json`

```json
{
  "manifest_version": "0.3",
  "name": "deskview-mcp",
  "display_name": "Deskview MCP",
  "version": "1.0.0",
  "description": "Direct access to the iPhone Continuity Camera Desk View feed for capturing physical workspace frames.",
  "long_description": "Deskview MCP gives Claude three tools for capturing the user's desk through the iPhone Continuity Camera overhead view. Capture instantly, wait for the scene to stabilize before capturing, or wait for a specific hand gesture before capturing. All detection runs natively on-device using AVFoundation and the Vision framework, so wait operations cost zero tokens until the actual frame is delivered.",
  "author": {
    "name": "Alexey Fedorov",
    "email": "alexey.max.fedorov@gmail.com",
    "url": "https://github.com/alexey-max-fedorov"
  },
  "repository": {
    "type": "git",
    "url": "https://github.com/alexey-max-fedorov/deskview-mcp"
  },
  "homepage": "https://github.com/alexey-max-fedorov/deskview-mcp",
  "documentation": "https://github.com/alexey-max-fedorov/deskview-mcp#readme",
  "support": "https://github.com/alexey-max-fedorov/deskview-mcp/issues",
  "icon": "icon.png",
  "keywords": ["camera", "desk-view", "continuity-camera", "vision", "macos", "agentic"],
  "license": "MIT",
  "server": {
    "type": "node",
    "entry_point": "server/index.js",
    "mcp_config": {
      "command": "node",
      "args": ["${__dirname}/server/index.js"],
      "env": {
        "DESKVIEW_BIN": "${__dirname}/bin/deskview-capture"
      }
    }
  },
  "tools": [
    {
      "name": "capture_desk_view",
      "description": "Capture a single frame from the Desk View camera right now."
    },
    {
      "name": "capture_on_stable",
      "description": "Wait until the scene stabilizes (motion stops for the specified duration), then capture one frame."
    },
    {
      "name": "capture_on_gesture",
      "description": "Wait until the specified hand gesture is detected, then capture one frame."
    }
  ],
  "compatibility": {
    "claude_desktop": ">=1.0.0",
    "platforms": ["darwin"],
    "runtimes": {
      "node": ">=18.0.0"
    }
  }
}
```

### Critical manifest details

- `manifest_version` must be `"0.3"`. That is the current spec.
- `server.type` is `"node"` (not `"binary"`). The MCP server is the Node.js process. The Swift binary is just a file inside the bundle that the Node server spawns. Don't confuse the two.
- `${__dirname}` is the official variable substitution for the bundle's install directory. It is replaced at runtime by Claude Desktop. Use it for both the entry point and the binary path.
- The `DESKVIEW_BIN` env var passes the resolved binary path to the Node server, which uses it in `child_process.spawn`.
- `tools` array entries only need `name` and optional `description`. Tool input schemas are defined at runtime by the MCP server, not in the manifest.
- `compatibility.platforms: ["darwin"]` is explicit macOS-only, since `darwin` is the platform string used by `process.platform`.

### `.mcpbignore`

Excludes dev-only files from the packaged bundle:

```
src/
swift/
node_modules/.cache/
*.log
.DS_Store
.git/
.github/
.vscode/
tsconfig.json
pnpm-lock.yaml
```

Note: `node_modules/` is **not** excluded because production deps must ship inside the bundle. Use `pnpm install --prod` before packing if needed, or rely on `pnpm prune --prod` to slim down before pack.

---

## 5. Tool Specifications

### 5.1 `capture_desk_view`

**Description:** Grab one frame from the Desk View camera right now and return it as a base64 PNG image content block.

**Input schema:**
```typescript
{
  type: "object",
  properties: {},
  additionalProperties: false
}
```

**Output (success):**
```typescript
{
  content: [
    {
      type: "image",
      data: "<base64 PNG data, no data: prefix>",
      mimeType: "image/png"
    },
    {
      type: "text",
      text: "Captured Desk View frame at 2026-05-06T19:23:45.123Z. Resolution: 1920x1440."
    }
  ]
}
```

**Output (error):**
```typescript
{
  content: [
    {
      type: "text",
      text: "<human-readable error explaining what went wrong and how to fix it>"
    }
  ],
  isError: true
}
```

**Error cases:**
- No Desk View device discovered: text content explains no iPhone connected via Continuity Camera, lists prerequisites
- Camera permission denied: text content with steps to grant access in System Settings, Privacy and Security, Camera
- Capture timeout (5s): text error explaining timeout

---

### 5.2 `capture_on_stable`

**Description:** Block until the scene stabilizes (motion below threshold for `stability_duration_ms` continuous milliseconds), then capture one frame.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    stability_duration_ms: {
      type: "number",
      default: 3000,
      minimum: 500,
      maximum: 30000,
      description: "How long the scene must remain still (motion below threshold) before capturing."
    },
    timeout_ms: {
      type: "number",
      default: 300000,
      minimum: 1000,
      maximum: 1800000,
      description: "Maximum total wait time. If reached without stabilization, returns the last frame with a timeout note."
    },
    sensitivity: {
      type: "string",
      enum: ["low", "medium", "high"],
      default: "medium",
      description: "How sensitive the motion detector is. Low is forgiving (5% pixel change tolerated), medium is balanced (2%), high is twitchy (0.5%)."
    }
  },
  additionalProperties: false
}
```

**Output (success):**
```typescript
{
  content: [
    { type: "image", data: "<base64 PNG>", mimeType: "image/png" },
    {
      type: "text",
      text: "Scene stabilized after 4.5s of motion, then 3000ms of stillness. Captured frame."
    }
  ]
}
```

**Output (timeout):**
```typescript
{
  content: [
    { type: "image", data: "<base64 PNG of last frame>", mimeType: "image/png" },
    {
      type: "text",
      text: "Stability timeout reached after 300000ms with continuous motion. Returning last captured frame."
    }
  ]
}
```

**Detection algorithm (Swift side):**

1. Subscribe to `AVCaptureVideoDataOutput` at 10fps (motion detection does not need 30fps).
2. For each incoming `CMSampleBuffer`, downsample to 64x48 grayscale `CIImage` for cheap diff math.
3. Compare against the previously stored downsampled buffer using per-pixel luminance delta. Count pixels with delta greater than 15 out of 0 to 255.
4. Convert count to percentage of total pixels (3072 total).
5. Sensitivity threshold mapping:
   - `low`: motion if greater than 5% changed
   - `medium`: motion if greater than 2% changed
   - `high`: motion if greater than 0.5% changed
6. Maintain a running counter of consecutive non-motion frames. If counter * frame_interval is at least `stability_duration_ms`, capture the next full-resolution frame and exit success.
7. If `timeout_ms` reached at any point, capture the next full-resolution frame and exit timeout.

---

### 5.3 `capture_on_gesture`

**Description:** Block until the specified hand gesture is detected and held for `hold_duration_ms`, then capture one frame.

**Input schema:**
```typescript
{
  type: "object",
  properties: {
    gesture: {
      type: "string",
      enum: ["thumbs_up", "peace", "ok_sign", "fist", "open_palm"],
      description: "Which hand gesture to wait for."
    },
    timeout_ms: {
      type: "number",
      default: 300000,
      minimum: 1000,
      maximum: 1800000
    },
    hold_duration_ms: {
      type: "number",
      default: 500,
      minimum: 100,
      maximum: 5000,
      description: "How long the gesture must be held continuously to count. Prevents false positives from brief flashes."
    }
  },
  required: ["gesture"],
  additionalProperties: false
}
```

**Gesture classification rules** (applied to landmarks from `VNHumanHandPoseObservation`):

| Gesture | Geometric rule |
|---|---|
| `thumbs_up` | Thumb tip Y above thumb MCP joint, AND all four other finger tips Y below their respective PIP joints |
| `peace` | Index tip Y above index PIP, AND middle tip Y above middle PIP, AND ring tip Y below ring PIP, AND pinky tip Y below pinky PIP |
| `ok_sign` | Distance(thumb tip, index tip) less than 30 normalized units, AND middle, ring, and pinky tips Y above their PIP joints |
| `fist` | All five finger tips Y below their respective MCP joints |
| `open_palm` | All five finger tips Y above their respective PIP joints |

Note: Vision returns normalized coordinates (0.0 to 1.0) in image space. "Y above" means lower Y value when the hand is held upright (top-of-image origin convention used by Vision).

**Output (success):**
```typescript
{
  content: [
    { type: "image", data: "<base64 PNG>", mimeType: "image/png" },
    {
      type: "text",
      text: "Detected gesture 'thumbs_up' held for 500ms. Captured frame at 2026-05-06T19:24:01.456Z."
    }
  ]
}
```

**Output (timeout):**
```typescript
{
  content: [
    {
      type: "text",
      text: "Gesture timeout reached after 300000ms. No frame captured. The gesture 'thumbs_up' was not detected for the required hold duration."
    }
  ],
  isError: true
}
```

**Detection algorithm (Swift side):**

1. Subscribe to `AVCaptureVideoDataOutput` at 15fps.
2. For each frame, run `VNDetectHumanHandPoseRequest` synchronously on the buffer.
3. If observation count is greater than 0, take the highest-confidence hand and pull all 21 landmarks (`VNHumanHandPoseObservation.recognizedPoints(.all)`).
4. Apply the classifier function for the requested gesture to the landmark dictionary.
5. If classifier returns true, increment the consecutive-match frame counter. If false, reset counter to 0.
6. When counter * frame_interval is at least `hold_duration_ms`, capture the next full-resolution frame and exit success.
7. If `timeout_ms` reached, exit with timeout (no frame).

---

## 6. Swift Binary Specification

### CLI surface

The binary is invoked by the Node MCP server with a subcommand and flags. All output for the MCP server goes to **stdout as a single JSON object**. All logs and diagnostics go to **stderr** (Claude Desktop logs stderr automatically).

```bash
# Subcommand: snapshot
./deskview-capture snapshot

# Subcommand: stable
./deskview-capture stable \
  --duration 3000 \
  --timeout 300000 \
  --sensitivity medium

# Subcommand: gesture
./deskview-capture gesture \
  --type thumbs_up \
  --hold 500 \
  --timeout 300000
```

### Output JSON schema

```json
{
  "status": "success" | "timeout" | "error",
  "image_base64": "<base64 PNG without data: prefix>" | null,
  "metadata": {
    "width": 1920,
    "height": 1440,
    "captured_at": "2026-05-06T19:23:45.123Z",
    "wait_duration_ms": 4523,
    "device_name": "iPhone 15 Pro Desk View"
  } | null,
  "error_code": null | "no_device" | "permission_denied" | "capture_failed" | "internal",
  "error_message": null | "<human-readable detail>"
}
```

### Device discovery

Two-tier discovery to handle the Desk View API correctly:

```swift
// Tier 1: Direct lookup of the dedicated DeskViewCamera device type
let primary = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.deskViewCamera],
    mediaType: .video,
    position: .unspecified
)

if let deskView = primary.devices.first {
    return deskView
}

// Tier 2: Fall back to the companionDeskViewCamera property of the main Continuity Camera
let fallback = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.continuityCamera],
    mediaType: .video,
    position: .unspecified
)

if let main = fallback.devices.first,
   let companion = main.companionDeskViewCamera {
    return companion
}

// Neither path succeeded
throw DeskviewError.noDevice
```

### Required frameworks and dependencies

System frameworks (all built-in, no install needed):
- `AVFoundation`: capture session, devices, video output
- `Vision`: `VNDetectHumanHandPoseRequest` and observations
- `CoreImage`: downsampling, pixel diff math
- `Foundation`: JSON encoding, dates

Swift Package dependency:
- `swift-argument-parser` (Apple, official) for clean CLI flag parsing

### `Package.swift`

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeskviewCapture",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "DeskviewCapture",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/DeskviewCapture"
        )
    ]
)
```

### Build script (`swift/build.sh`)

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "Building DeskviewCapture for arm64-apple-macosx..."
swift build -c release --arch arm64

OUT_DIR="../bin"
mkdir -p "$OUT_DIR"
cp .build/arm64-apple-macosx/release/DeskviewCapture "$OUT_DIR/deskview-capture"
chmod +x "$OUT_DIR/deskview-capture"

echo "Built: $OUT_DIR/deskview-capture"
```

### Camera permission string

The compiled binary needs an `Info.plist` entry for `NSCameraUsageDescription` so the camera permission prompt has friendly copy:

```
NSCameraUsageDescription = "Deskview MCP captures frames from the iPhone Continuity Camera Desk View so Claude can see your physical workspace."
```

If embedding `Info.plist` cleanly into a Swift Package executable proves difficult, fall back to the system default prompt. The user will still get prompted, just with generic system language.

---

## 7. Node MCP Server Specification

### Dependencies

```bash
pnpm add @modelcontextprotocol/sdk zod
pnpm add -D typescript @types/node tsx
```

### `package.json`

```json
{
  "name": "deskview-mcp",
  "version": "1.0.0",
  "type": "module",
  "main": "server/index.js",
  "scripts": {
    "build:server": "tsc",
    "build:swift": "cd swift && ./build.sh",
    "build": "pnpm build:swift && pnpm build:server",
    "package": "pnpm build && pnpm dlx @anthropic-ai/mcpb pack",
    "dev": "tsx src/index.ts",
    "clean": "rm -rf server/ bin/"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.4.0"
  },
  "engines": {
    "node": ">=18"
  }
}
```

### `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "node",
    "outDir": "./server",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "declaration": false,
    "sourceMap": false,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "server", "swift", "bin"]
}
```

### `src/index.ts`, server entry

Key responsibilities:
1. Create an MCP `Server` instance from `@modelcontextprotocol/sdk`.
2. Register `ListToolsRequestSchema` handler returning the three tools with their full input schemas.
3. Register `CallToolRequestSchema` handler that routes to `runCapture()` based on tool name.
4. Connect via `StdioServerTransport`.

Skeleton:

```typescript
#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { runCapture } from "./capture.js";

const server = new Server(
  { name: "deskview-mcp", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    /* Full tool definitions per Section 5 */
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  return await runCapture(name, args ?? {});
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

### `src/capture.ts`, Swift binary wrapper

Responsibilities:
1. Resolve the binary path from `process.env.DESKVIEW_BIN` (set by the manifest's `mcp_config.env`).
2. Translate the MCP tool call into a Swift CLI invocation.
3. Spawn via `child_process.spawn` (NOT `exec`, since base64 PNG can exceed exec buffer limits).
4. Collect stdout into a buffer.
5. Pipe stderr through to the Node server's stderr (Claude Desktop captures it for logs).
6. On exit, parse stdout JSON and convert to MCP content blocks.
7. Hard-kill the child process at `timeout_ms + 5000ms` as a safety net.

Implementation notes:
- Always validate `DESKVIEW_BIN` is set and points to an existing executable file at startup. If missing, the server should respond to every tool call with a clear error explaining the bundle is broken.
- Use `spawn` with `{ stdio: ["ignore", "pipe", "pipe"] }`.
- Use a `Promise` that resolves on the binary's `close` event, with the buffered stdout JSON.

---

## 8. Permissions

### macOS Camera

The Swift binary triggers the standard macOS camera permission prompt the first time it accesses any `AVCaptureDevice`. The OS controls the prompt's exact wording. The user's choice is stored at the OS level under TCC (Transparency, Consent, and Control). The binary is identified by its bundle ID or path.

If the user denies, future calls return `permission_denied`. The Node server surfaces a text content block telling the user how to fix it: System Settings, Privacy and Security, Camera.

There is no programmatic way to re-prompt once denied. Document this in the README.

### Continuity Camera prerequisites (user-side, not enforced)

These are documented in the README, not validated by the extension:

- iPhone running iOS 16 or later
- Mac running macOS 13 or later
- Both devices signed into the same iCloud account
- Bluetooth and Wi-Fi enabled on both
- iPhone physically mounted above the desk (Belkin MagSafe Continuity Camera mount or equivalent)
- Desk View enabled in Control Center on the Mac

If any prerequisite is unmet, the extension returns `no_device` with a helpful error message pointing to the README.

---

## 9. Build and Package Process

### Local development

```bash
# One-time
pnpm install

# Iterate on TypeScript only
pnpm dev            # tsx watch mode

# Full build
pnpm build          # Swift binary + TS compile

# Package as .mcpb
pnpm package        # full build + mcpb pack
```

### Package output

The `mcpb pack` command produces `deskview-mcp-1.0.0.mcpb` in the project root. Internal structure of that zip:

```
deskview-mcp-1.0.0.mcpb (zip archive)
├── manifest.json
├── package.json
├── icon.png
├── README.md
├── server/
│   └── index.js          # Compiled MCP server
├── bin/
│   └── deskview-capture  # Compiled arm64 binary
└── node_modules/         # Production-only dependencies
```

### What ships vs. what doesn't

| Included | Excluded (via `.mcpbignore`) |
|---|---|
| `manifest.json` | `src/` (TS source) |
| `package.json` | `swift/` (Swift source) |
| `server/` (compiled JS) | `tsconfig.json` |
| `bin/` (compiled binary) | `pnpm-lock.yaml` |
| `node_modules/` (prod deps) | `.git/`, `.github/`, `.vscode/` |
| `icon.png`, `README.md` | `*.log`, `.DS_Store` |

### Local install for testing

1. In Claude Desktop: Settings, Extensions, Advanced settings, Extension Developer
2. Click "Install Extension..."
3. Select the `.mcpb` file
4. Confirm install
5. Tools should appear in the next chat

To iterate, uninstall and reinstall after each repackage. Use the Extension Developer panel to see runtime logs.

---

## 10. Testing

### Manual test matrix

| Scenario | Expected result |
|---|---|
| Install bundle, no iPhone connected | `capture_desk_view` returns `isError` text explaining no Desk View device plus prerequisites |
| Install bundle, deny camera permission on first call | Returns `permission_denied` error with System Settings instructions |
| All permissions granted, Desk View active, call `capture_desk_view` | Returns image content block within 2s, resolution 1920x1440 |
| `capture_on_stable` with hand actively moving over desk | Blocks. Once hand removed and 3s pass, returns frame |
| `capture_on_stable` with `timeout_ms: 5000` and constant motion | After 5s, returns last frame with timeout note |
| `capture_on_gesture` with `thumbs_up`, no gesture shown | Blocks for full timeout, returns timeout error |
| `capture_on_gesture` with brief flash of thumbs up (under 500ms) | Keeps waiting (debounce works) |
| `capture_on_gesture` with thumbs up held 1s | Returns frame within 500ms of gesture appearing |
| Each gesture type (thumbs_up, peace, ok_sign, fist, open_palm) | Detected reliably under good lighting |
| Run `capture_desk_view` 10 times in quick succession | All complete cleanly, no zombie processes |

### Logs and debugging

- Swift binary logs go to stderr, surfaced in Claude Desktop's extension logs panel
- Node server can use `console.error` for additional diagnostics (also captured)
- Test the Swift binary standalone via Terminal: `./bin/deskview-capture snapshot | jq`. Should print clean JSON.

---

## 11. Distribution

### v1

- Public GitHub repo at `github.com/alexey-max-fedorov/deskview-mcp`
- Each tagged release attaches the `.mcpb` file as a release asset
- README documents install steps, prerequisites, troubleshooting

### v1.1+

- Submit to Anthropic's desktop extension directory (form linked in their support docs)
- Once accepted, auto-updates handled by the directory mechanism

---

## 12. Implementation Order (for Claude Code)

Build in this exact sequence so each step leaves a working, testable state. **Do not batch steps.**

1. **Repo scaffold.** Create directory structure, `package.json` (with pnpm engines), `tsconfig.json`, `manifest.json`, `.mcpbignore`, `.gitignore`, empty `README.md`. Run `pnpm install`.

2. **Swift project init.** Create `swift/Package.swift`, `swift/Sources/DeskviewCapture/main.swift` with `ArgumentParser` setup defining the three subcommands. Each subcommand prints a fake JSON success response. Build via `swift/build.sh`. Verify: `./bin/deskview-capture snapshot | jq` returns valid JSON.

3. **Node MCP server skeleton.** Implement `src/index.ts` with `Server` setup, `ListToolsRequestSchema` returning the three tools (full input schemas from Section 5), and a stub `CallToolRequestSchema` that returns hardcoded text for each tool name. Compile to `server/index.js`. Verify the server starts and responds to MCP `tools/list` over stdio.

4. **Capture wrapper.** Implement `src/capture.ts` that spawns the (still-stubbed) Swift binary, reads stdout, parses the fake JSON, and converts to MCP content blocks. Wire it into `CallToolRequestSchema`. Now end-to-end: Node receives tool call, spawns Swift, returns stub data.

5. **First bundle install.** Run `pnpm package`, install the resulting `.mcpb` in Claude Desktop via developer mode. Confirm all three tools appear and return stub responses when called.

6. **Real `snapshot` in Swift.** Implement `DeskViewSession.swift` with device discovery (both tiers), capture session setup, single-frame capture via `AVCapturePhotoOutput` or still image extraction from `AVCaptureVideoDataOutput`, PNG encoding, base64 output. Wire into the `snapshot` subcommand. Test in Terminal first, then via Claude.

7. **Real `stable` in Swift.** Implement `StableDetector.swift` with the 10fps video data output, downsample-and-diff loop, sensitivity thresholds, stability counter. Wire into `stable` subcommand. Test via Terminal and Claude.

8. **Real `gesture` in Swift.** Implement `GestureDetector.swift` with `VNDetectHumanHandPoseRequest`, the five gesture classifiers from Section 5.3, hold debounce. Wire into `gesture` subcommand. Test each gesture via Claude.

9. **End-to-end QA.** Run the full test matrix from Section 10. Fix anything that fails.

10. **Polish.** Write the README (install steps, prerequisites, troubleshooting, screenshots). Make the icon. Tag v1.0.0 in git. Cut a GitHub release with the `.mcpb` attached.

Each step should produce a working artifact. If a step fails, fix before moving on. Don't try to write all the Swift logic before the Node server works end-to-end.

---

## 13. Constraints and Conventions

- **Package manager: pnpm only.** Never npm. Never yarn. Lockfile is `pnpm-lock.yaml`.
- **Manifest version: `0.3`.** Don't downgrade.
- **Node version:** 18 or higher (matches what Claude Desktop ships)
- **Swift version:** 5.9 or higher
- **macOS target:** 13.0 or higher (Desk View requires it)
- **Architecture:** arm64 only for v1 (M-series Macs)
- **No em dashes** in any committed text content (README, comments, error messages, manifest descriptions). Use commas, parens, or sentence breaks. This applies to all human-readable strings in the project.
- **Stdout is sacred** in the Swift binary: only valid JSON goes there. All logs go to stderr.
- **No telemetry, no external network calls.** Camera frames stay 100% local. The bundle should make zero outbound requests during normal operation.
- **No bundled secrets, API keys, or credentials.** This extension does not need any.
- **Tool input schemas live in `src/index.ts`,** not in `manifest.json`. The manifest only lists tool names and one-line descriptions.
- **Variable substitution in manifest:** use `${__dirname}` for paths inside the bundle. Don't hardcode paths.

---

## 14. Future Enhancements (Out of Scope for v1)

Tracked for v2+ planning:

- Universal binary (arm64 plus x86_64) for Intel Mac compatibility
- Region-of-interest cropping (`region: { x, y, w, h }` param on all tools)
- Drawn shape detection (star, checkmark, x, circle) via `VNDetectContoursRequest`
- Burst mode: capture N frames over M seconds, return the sharpest by Laplacian variance
- Custom user-trained gestures via short recording, then a CoreML model
- Live ambient mode: low-fps stream of frames pushed to Claude over the lifetime of a session (requires MCP server-initiated messages, currently a protocol limitation)
- Video clip capture (short MP4 of the moment a gesture or stability triggers)
- macOS service registration for the binary so it has a stable TCC identity across versions

---

End of PRD.
