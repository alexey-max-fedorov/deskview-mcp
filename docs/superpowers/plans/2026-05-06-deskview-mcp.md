# Deskview MCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Dispatch each task to a fresh `sonnet[1m]` subagent (model: `claude-sonnet-4-6`, 1M context). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Claude Desktop Extension (.mcpb bundle) exposing 3 MCP tools that capture frames from the iPhone Continuity Camera Desk View, with on-device stability and gesture triggers.

**Architecture:** A Node.js MCP server (TypeScript, stdio transport) spawns a compiled Swift CLI binary that owns AVFoundation, Vision, and CoreImage work. Node handles the MCP protocol; Swift handles camera I/O. The bundle ships the compiled arm64 binary plus production `node_modules`.

**Tech Stack:** TypeScript, Node 18+, `@modelcontextprotocol/sdk`, `zod`, `vitest`, `pnpm`, Swift 5.9+, AVFoundation, Vision, CoreImage, `swift-argument-parser`, `@anthropic-ai/mcpb`.

**Hard Constraints (do not violate):**
- pnpm only. Never npm. Never yarn. Lockfile is `pnpm-lock.yaml`.
- Manifest version is `"0.3"`. Do not downgrade.
- arm64 only. macOS 13+. Swift 5.9+. Node 18+.
- No em dashes in any committed text (README, comments, error strings, manifest descriptions, commit messages, plan files). Use commas, parens, or sentence breaks.
- Stdout in the Swift binary is reserved for one JSON object. All logs and diagnostics go to stderr.
- Tool input schemas live in `src/index.ts`, not in `manifest.json`. The manifest only lists tool name + one-line description.
- Use `${__dirname}` for paths inside the bundle. Never hardcode.
- No telemetry, no external network calls. Frames stay 100% local.
- Subagents must run `pnpm` (not `npm`). If a subagent reaches for `npm`, abort and re-prompt.

---

## File Map

Each file has one clear responsibility. Files that change together live together.

```
deskview-mcp/
├── manifest.json                              # MCPB v0.3 manifest, server config
├── package.json                               # Node deps, scripts (build/package/test)
├── pnpm-lock.yaml                             # Committed lockfile
├── tsconfig.json                              # Strict TS, ES2022, outDir=server/
├── vitest.config.ts                           # Test runner config
├── .mcpbignore                                # Excludes src/, swift/, etc. from pack
├── .gitignore                                 # Excludes server/, bin/, node_modules/, etc.
├── README.md                                  # Install + prerequisites + troubleshooting
├── icon.png                                   # 256x256 extension icon
│
├── src/                                       # TypeScript source
│   ├── index.ts                               # MCP server entry, ListTools/CallTool handlers
│   ├── capture.ts                             # Spawns Swift binary, parses JSON, maps to MCP content
│   ├── schemas.ts                             # Zod schemas for tool inputs (single source of truth)
│   ├── types.ts                               # Shared TS types (SwiftResult, McpContent)
│   └── __tests__/
│       ├── capture.test.ts                    # Capture wrapper tests using stub binaries
│       └── fixtures/
│           ├── stub-success.sh                # Prints success JSON, exits 0
│           ├── stub-timeout.sh                # Prints timeout JSON, exits 0
│           ├── stub-error.sh                  # Prints error JSON, exits 0
│           ├── stub-crash.sh                  # Exits non-zero with garbage on stdout
│           └── tiny.png.b64                   # 1x1 PNG base64 fixture
│
├── server/                                    # tsc output (gitignored, packed into .mcpb)
│   └── index.js
│
├── swift/                                     # Swift source (NOT shipped in bundle)
│   ├── Package.swift                          # Swift package, ArgumentParser dep
│   ├── build.sh                               # Builds release arm64 → ../bin/deskview-capture
│   ├── Sources/
│   │   └── DeskviewCapture/
│   │       ├── main.swift                     # ArgumentParser CLI entry, three subcommands
│   │       ├── DeskViewSession.swift          # AVCaptureSession setup + two-tier device discovery
│   │       ├── StableDetector.swift           # Pure pixel-diff math + AV plumbing
│   │       ├── GestureDetector.swift          # Pure landmark classifiers + Vision plumbing
│   │       ├── ImageEncoder.swift             # CMSampleBuffer → PNG Data → base64 String
│   │       ├── OutputJSON.swift               # Codable result struct, prints to stdout
│   │       └── DeskviewError.swift            # Typed errors mapped to error_code strings
│   └── Tests/
│       └── DeskviewCaptureTests/
│           ├── GestureClassifierTests.swift   # Pure-function tests on landmark dictionaries
│           └── StableDetectorTests.swift      # Pure-function tests on synthetic CIImages
│
├── bin/                                       # Compiled binary (gitignored, packed into .mcpb)
│   └── deskview-capture
│
└── node_modules/                              # Production deps (packed into .mcpb)
```

---

## Task Decomposition Strategy

This plan front-loads the **end-to-end skeleton** (stub Swift binary, Node wrapper, packaged .mcpb installed in Claude Desktop) before adding real camera logic. That way every later task builds on a known-good integration.

For Swift, real AVFoundation code is hard to unit-test (requires hardware). The plan extracts pure math (gesture classifiers, pixel diff) into pure functions and unit-tests those. AVFoundation plumbing is verified manually via the binary CLI.

For Node, the spawn wrapper is unit-tested using shell-script stub binaries that print known JSON. This is the most failure-prone seam, so it gets real test coverage.

---

# PHASE 0: Repo Scaffold

### Task 1: Initialize repo structure and gitignore

**Files:**
- Create: `.gitignore`
- Create: `README.md`
- Create: `package.json`
- Create: `tsconfig.json`
- Create: `.mcpbignore`

- [ ] **Step 1: Create `.gitignore`**

```
node_modules/
server/
bin/
*.mcpb
.DS_Store
*.log
swift/.build/
swift/Package.resolved
.vscode/
.idea/
```

- [ ] **Step 2: Create minimal `README.md`**

```markdown
# Deskview MCP

A Claude Desktop Extension that captures frames from the iPhone Continuity Camera Desk View.

Status: in development. See `deskview-mcp-prd.md` for full spec.

## Requirements

- macOS 13 or later, Apple Silicon (arm64)
- iPhone running iOS 16 or later, signed into the same iCloud account
- Bluetooth and Wi-Fi enabled on both devices
- Desk View enabled in Mac Control Center

## Build

Requires pnpm and Swift 5.9 or later.

\`\`\`bash
pnpm install
pnpm build
pnpm package
\`\`\`
```

- [ ] **Step 3: Create `package.json`**

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
    "test": "vitest run",
    "test:watch": "vitest",
    "clean": "rm -rf server/ bin/ swift/.build *.mcpb"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "tsx": "^4.0.0",
    "typescript": "^5.4.0",
    "vitest": "^1.6.0"
  },
  "engines": {
    "node": ">=18",
    "pnpm": ">=8"
  },
  "packageManager": "pnpm@9.0.0"
}
```

- [ ] **Step 4: Create `tsconfig.json`**

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
    "resolveJsonModule": true,
    "types": ["node", "vitest/globals"]
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "server", "swift", "bin", "src/__tests__"]
}
```

- [ ] **Step 5: Create `.mcpbignore`**

```
src/
swift/
node_modules/.cache/
*.log
.DS_Store
.git/
.github/
.vscode/
.idea/
tsconfig.json
vitest.config.ts
pnpm-lock.yaml
deskview-mcp-prd.md
docs/
*.mcpb
```

- [ ] **Step 6: Verify**

Run: `cat .gitignore .mcpbignore && jq . package.json && jq . tsconfig.json`
Expected: All files print without errors. JSON is valid.

- [ ] **Step 7: Commit**

```bash
git add .gitignore README.md package.json tsconfig.json .mcpbignore
git commit -m "chore: scaffold repo structure"
```

---

### Task 2: Install Node dependencies

**Files:**
- Create: `pnpm-lock.yaml`
- Create: `node_modules/`

- [ ] **Step 1: Install dependencies via pnpm**

Run: `pnpm install`
Expected: Resolves and installs without errors. Creates `pnpm-lock.yaml` and `node_modules/`.

- [ ] **Step 2: Verify pnpm was used (not npm/yarn)**

Run: `ls -la | grep -E 'lock\.|lockb'`
Expected: Only `pnpm-lock.yaml` exists. No `package-lock.json`. No `yarn.lock`. No `bun.lockb`.

If any other lockfile exists, delete it and re-run `pnpm install`.

- [ ] **Step 3: Verify key deps resolved**

Run: `pnpm list --depth 0`
Expected: Lists `@modelcontextprotocol/sdk`, `zod`, `typescript`, `tsx`, `vitest`, `@types/node`.

- [ ] **Step 4: Commit lockfile**

```bash
git add pnpm-lock.yaml
git commit -m "chore: add pnpm lockfile"
```

---

### Task 3: Add manifest.json and vitest config

**Files:**
- Create: `manifest.json`
- Create: `vitest.config.ts`

- [ ] **Step 1: Create `manifest.json` per PRD Section 4**

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

- [ ] **Step 2: Validate manifest is well-formed JSON**

Run: `jq . manifest.json > /dev/null && echo OK`
Expected: prints `OK`.

- [ ] **Step 3: Create `vitest.config.ts`**

```typescript
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    globals: true,
    include: ["src/**/__tests__/**/*.test.ts"],
    testTimeout: 10000,
  },
});
```

- [ ] **Step 4: Verify test runner picks up zero tests cleanly**

Run: `pnpm test`
Expected: Exits 0 with "No test files found" or "0 tests ran". The runner is wired up correctly.

- [ ] **Step 5: Commit**

```bash
git add manifest.json vitest.config.ts
git commit -m "chore: add MCPB manifest and vitest config"
```

---

# PHASE 1: Swift CLI Skeleton (Stub JSON)

### Task 4: Initialize Swift package and ArgumentParser CLI skeleton

**Files:**
- Create: `swift/Package.swift`
- Create: `swift/Sources/DeskviewCapture/main.swift`
- Create: `swift/Sources/DeskviewCapture/OutputJSON.swift`
- Create: `swift/Sources/DeskviewCapture/DeskviewError.swift`

- [ ] **Step 1: Create `swift/Package.swift`**

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
        ),
        .testTarget(
            name: "DeskviewCaptureTests",
            dependencies: ["DeskviewCapture"],
            path: "Tests/DeskviewCaptureTests"
        )
    ]
)
```

- [ ] **Step 2: Create `swift/Sources/DeskviewCapture/DeskviewError.swift`**

```swift
import Foundation

enum DeskviewError: Error {
    case noDevice
    case permissionDenied
    case captureFailed(String)
    case timeout
    case internalError(String)

    var code: String {
        switch self {
        case .noDevice: return "no_device"
        case .permissionDenied: return "permission_denied"
        case .captureFailed: return "capture_failed"
        case .timeout: return "timeout"
        case .internalError: return "internal"
        }
    }

    var message: String {
        switch self {
        case .noDevice:
            return "No Desk View camera found. Connect an iPhone via Continuity Camera and enable Desk View in Control Center."
        case .permissionDenied:
            return "Camera permission denied. Grant access in System Settings, Privacy and Security, Camera."
        case .captureFailed(let detail):
            return "Capture failed: \(detail)"
        case .timeout:
            return "Operation timed out."
        case .internalError(let detail):
            return "Internal error: \(detail)"
        }
    }
}
```

- [ ] **Step 3: Create `swift/Sources/DeskviewCapture/OutputJSON.swift`**

```swift
import Foundation

struct CaptureMetadata: Codable {
    let width: Int
    let height: Int
    let captured_at: String
    let wait_duration_ms: Int
    let device_name: String
}

struct CaptureResult: Codable {
    let status: String   // "success" | "timeout" | "error"
    let image_base64: String?
    let metadata: CaptureMetadata?
    let error_code: String?
    let error_message: String?

    static func success(image: String, metadata: CaptureMetadata) -> CaptureResult {
        CaptureResult(status: "success", image_base64: image, metadata: metadata,
                      error_code: nil, error_message: nil)
    }

    static func timeout(image: String?, metadata: CaptureMetadata?) -> CaptureResult {
        CaptureResult(status: "timeout", image_base64: image, metadata: metadata,
                      error_code: "timeout", error_message: "Timeout reached.")
    }

    static func error(_ err: DeskviewError) -> CaptureResult {
        CaptureResult(status: "error", image_base64: nil, metadata: nil,
                      error_code: err.code, error_message: err.message)
    }
}

func emit(_ result: CaptureResult) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        let data = try encoder.encode(result)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write("\n".data(using: .utf8)!)
    } catch {
        let fallback = "{\"status\":\"error\",\"error_code\":\"internal\",\"error_message\":\"json encode failed\"}\n"
        FileHandle.standardOutput.write(fallback.data(using: .utf8)!)
    }
}

func logStderr(_ msg: String) {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
}
```

- [ ] **Step 4: Create `swift/Sources/DeskviewCapture/main.swift` with three stub subcommands**

```swift
import Foundation
import ArgumentParser

struct Deskview: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deskview-capture",
        abstract: "Capture frames from the iPhone Continuity Camera Desk View.",
        subcommands: [Snapshot.self, Stable.self, Gesture.self]
    )
}

struct Snapshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "snapshot",
        abstract: "Capture one frame immediately."
    )

    func run() throws {
        logStderr("snapshot: stub")
        let metadata = CaptureMetadata(
            width: 0, height: 0,
            captured_at: ISO8601DateFormatter().string(from: Date()),
            wait_duration_ms: 0,
            device_name: "stub"
        )
        emit(CaptureResult.success(image: "", metadata: metadata))
    }
}

struct Stable: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stable",
        abstract: "Capture once the scene is stable."
    )

    @Option(name: .long) var duration: Int = 3000
    @Option(name: .long) var timeout: Int = 300000
    @Option(name: .long) var sensitivity: String = "medium"

    func run() throws {
        logStderr("stable: stub duration=\(duration) timeout=\(timeout) sensitivity=\(sensitivity)")
        let metadata = CaptureMetadata(
            width: 0, height: 0,
            captured_at: ISO8601DateFormatter().string(from: Date()),
            wait_duration_ms: 0,
            device_name: "stub"
        )
        emit(CaptureResult.success(image: "", metadata: metadata))
    }
}

struct Gesture: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gesture",
        abstract: "Capture once a gesture is detected."
    )

    @Option(name: .long) var type: String
    @Option(name: .long) var hold: Int = 500
    @Option(name: .long) var timeout: Int = 300000

    func run() throws {
        logStderr("gesture: stub type=\(type) hold=\(hold) timeout=\(timeout)")
        let metadata = CaptureMetadata(
            width: 0, height: 0,
            captured_at: ISO8601DateFormatter().string(from: Date()),
            wait_duration_ms: 0,
            device_name: "stub"
        )
        emit(CaptureResult.success(image: "", metadata: metadata))
    }
}

Deskview.main()
```

- [ ] **Step 5: Build via Swift Package Manager**

Run: `cd swift && swift build -c release --arch arm64`
Expected: Build succeeds. Binary appears at `swift/.build/arm64-apple-macosx/release/DeskviewCapture`.

- [ ] **Step 6: Run binary directly to verify JSON output**

Run: `cd swift && ./.build/arm64-apple-macosx/release/DeskviewCapture snapshot | jq .`
Expected: Pretty-prints a valid JSON object with `status: "success"`, `image_base64: ""`, `metadata` populated, no error fields.

- [ ] **Step 7: Verify all three subcommands**

```bash
cd swift
./.build/arm64-apple-macosx/release/DeskviewCapture snapshot | jq .status
./.build/arm64-apple-macosx/release/DeskviewCapture stable --duration 1000 --timeout 5000 --sensitivity low | jq .status
./.build/arm64-apple-macosx/release/DeskviewCapture gesture --type thumbs_up --hold 200 --timeout 5000 | jq .status
```
Expected: All three print `"success"`.

- [ ] **Step 8: Commit**

```bash
git add swift/Package.swift swift/Sources
git commit -m "feat(swift): add CLI skeleton with three stub subcommands"
```

---

### Task 5: Add build.sh that produces bin/deskview-capture

**Files:**
- Create: `swift/build.sh`

- [ ] **Step 1: Create `swift/build.sh`**

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

- [ ] **Step 2: Make executable and run**

Run: `chmod +x swift/build.sh && ./swift/build.sh`
Expected: Prints "Built: ../bin/deskview-capture". `bin/deskview-capture` exists and is executable.

- [ ] **Step 3: Smoke-test from project root via the canonical path**

Run: `./bin/deskview-capture snapshot | jq .status`
Expected: `"success"`.

- [ ] **Step 4: Verify pnpm script works end-to-end**

Run: `pnpm build:swift`
Expected: Same output as Step 2. No errors.

- [ ] **Step 5: Commit**

```bash
git add swift/build.sh
git commit -m "chore(swift): add release build script that emits bin/deskview-capture"
```

---

### Task 6: Add Swift unit test scaffolding

**Files:**
- Create: `swift/Tests/DeskviewCaptureTests/SmokeTests.swift`

- [ ] **Step 1: Create a smoke test that proves the test target compiles**

```swift
import XCTest
@testable import DeskviewCapture

final class SmokeTests: XCTestCase {
    func testErrorCodes() {
        XCTAssertEqual(DeskviewError.noDevice.code, "no_device")
        XCTAssertEqual(DeskviewError.permissionDenied.code, "permission_denied")
        XCTAssertEqual(DeskviewError.timeout.code, "timeout")
    }

    func testCaptureResultEncodesAllFields() throws {
        let metadata = CaptureMetadata(
            width: 100, height: 50,
            captured_at: "2026-05-06T00:00:00Z",
            wait_duration_ms: 1234,
            device_name: "test"
        )
        let result = CaptureResult.success(image: "abc", metadata: metadata)
        let data = try JSONEncoder().encode(result)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("\"status\":\"success\""))
        XCTAssertTrue(json.contains("\"image_base64\":\"abc\""))
        XCTAssertTrue(json.contains("\"width\":100"))
    }
}
```

- [ ] **Step 2: Run tests**

Run: `cd swift && swift test`
Expected: Both tests pass. Test target compiles cleanly.

- [ ] **Step 3: Commit**

```bash
git add swift/Tests
git commit -m "test(swift): add smoke tests for error codes and JSON encoding"
```

---

# PHASE 2: Node MCP Server (Stub Pipeline End-to-End)

### Task 7: Define shared types and Zod schemas

**Files:**
- Create: `src/types.ts`
- Create: `src/schemas.ts`

- [ ] **Step 1: Create `src/types.ts`**

```typescript
export interface SwiftMetadata {
  width: number;
  height: number;
  captured_at: string;
  wait_duration_ms: number;
  device_name: string;
}

export type SwiftStatus = "success" | "timeout" | "error";

export type SwiftErrorCode =
  | "no_device"
  | "permission_denied"
  | "capture_failed"
  | "timeout"
  | "internal";

export interface SwiftResult {
  status: SwiftStatus;
  image_base64: string | null;
  metadata: SwiftMetadata | null;
  error_code: SwiftErrorCode | null;
  error_message: string | null;
}

export interface ImageContent {
  type: "image";
  data: string;
  mimeType: "image/png";
}

export interface TextContent {
  type: "text";
  text: string;
}

export type McpContent = ImageContent | TextContent;

export interface McpToolResponse {
  content: McpContent[];
  isError?: boolean;
}

export type ToolName = "capture_desk_view" | "capture_on_stable" | "capture_on_gesture";
```

- [ ] **Step 2: Create `src/schemas.ts`**

```typescript
import { z } from "zod";

export const captureDeskViewInput = z.object({}).strict();

export const captureOnStableInput = z
  .object({
    stability_duration_ms: z.number().min(500).max(30000).default(3000),
    timeout_ms: z.number().min(1000).max(1800000).default(300000),
    sensitivity: z.enum(["low", "medium", "high"]).default("medium"),
  })
  .strict();

export const captureOnGestureInput = z
  .object({
    gesture: z.enum(["thumbs_up", "peace", "ok_sign", "fist", "open_palm"]),
    timeout_ms: z.number().min(1000).max(1800000).default(300000),
    hold_duration_ms: z.number().min(100).max(5000).default(500),
  })
  .strict();

// JSON Schema mirrors used in the ListTools response.
export const captureDeskViewJsonSchema = {
  type: "object",
  properties: {},
  additionalProperties: false,
} as const;

export const captureOnStableJsonSchema = {
  type: "object",
  properties: {
    stability_duration_ms: {
      type: "number",
      default: 3000,
      minimum: 500,
      maximum: 30000,
      description:
        "How long the scene must remain still (motion below threshold) before capturing.",
    },
    timeout_ms: {
      type: "number",
      default: 300000,
      minimum: 1000,
      maximum: 1800000,
      description:
        "Maximum total wait time. If reached without stabilization, returns the last frame with a timeout note.",
    },
    sensitivity: {
      type: "string",
      enum: ["low", "medium", "high"],
      default: "medium",
      description:
        "How sensitive the motion detector is. Low is forgiving (5% pixel change tolerated), medium is balanced (2%), high is twitchy (0.5%).",
    },
  },
  additionalProperties: false,
} as const;

export const captureOnGestureJsonSchema = {
  type: "object",
  properties: {
    gesture: {
      type: "string",
      enum: ["thumbs_up", "peace", "ok_sign", "fist", "open_palm"],
      description: "Which hand gesture to wait for.",
    },
    timeout_ms: {
      type: "number",
      default: 300000,
      minimum: 1000,
      maximum: 1800000,
    },
    hold_duration_ms: {
      type: "number",
      default: 500,
      minimum: 100,
      maximum: 5000,
      description:
        "How long the gesture must be held continuously to count. Prevents false positives from brief flashes.",
    },
  },
  required: ["gesture"],
  additionalProperties: false,
} as const;
```

- [ ] **Step 3: Verify TypeScript compiles**

Run: `pnpm tsc --noEmit`
Expected: No type errors.

- [ ] **Step 4: Commit**

```bash
git add src/types.ts src/schemas.ts
git commit -m "feat(server): add shared types and zod schemas for tool inputs"
```

---

### Task 8: Test capture wrapper with stub binary fixtures (TDD)

**Files:**
- Create: `src/__tests__/fixtures/stub-success.sh`
- Create: `src/__tests__/fixtures/stub-timeout.sh`
- Create: `src/__tests__/fixtures/stub-error.sh`
- Create: `src/__tests__/fixtures/stub-crash.sh`
- Create: `src/__tests__/fixtures/tiny.png.b64`
- Create: `src/__tests__/capture.test.ts`

- [ ] **Step 1: Create the tiny PNG base64 fixture**

Run:

```bash
mkdir -p src/__tests__/fixtures
# 1x1 transparent PNG, captured once and committed.
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=' > src/__tests__/fixtures/tiny.png.b64
```

Expected: File exists, ~120 bytes, single line.

- [ ] **Step 2: Create `src/__tests__/fixtures/stub-success.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
B64=$(cat "$(dirname "$0")/tiny.png.b64")
cat <<EOF
{"status":"success","image_base64":"$B64","metadata":{"width":1920,"height":1440,"captured_at":"2026-05-06T19:23:45.123Z","wait_duration_ms":42,"device_name":"iPhone 15 Pro Desk View"},"error_code":null,"error_message":null}
EOF
```

Run: `chmod +x src/__tests__/fixtures/stub-success.sh`
Verify: `./src/__tests__/fixtures/stub-success.sh | jq .status` prints `"success"`.

- [ ] **Step 3: Create `src/__tests__/fixtures/stub-timeout.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
B64=$(cat "$(dirname "$0")/tiny.png.b64")
cat <<EOF
{"status":"timeout","image_base64":"$B64","metadata":{"width":1920,"height":1440,"captured_at":"2026-05-06T19:24:00.000Z","wait_duration_ms":300000,"device_name":"iPhone 15 Pro Desk View"},"error_code":"timeout","error_message":"Stability timeout reached"}
EOF
```

Run: `chmod +x src/__tests__/fixtures/stub-timeout.sh`

- [ ] **Step 4: Create `src/__tests__/fixtures/stub-error.sh`**

```bash
#!/usr/bin/env bash
cat <<'EOF'
{"status":"error","image_base64":null,"metadata":null,"error_code":"no_device","error_message":"No Desk View camera found."}
EOF
```

Run: `chmod +x src/__tests__/fixtures/stub-error.sh`

- [ ] **Step 5: Create `src/__tests__/fixtures/stub-crash.sh`**

```bash
#!/usr/bin/env bash
echo "this is not json" >&2
echo "garbage on stdout"
exit 17
```

Run: `chmod +x src/__tests__/fixtures/stub-crash.sh`

- [ ] **Step 6: Write failing tests in `src/__tests__/capture.test.ts`**

```typescript
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
```

- [ ] **Step 7: Run tests to confirm they FAIL**

Run: `pnpm test`
Expected: All 7 tests fail with "Cannot find module '../capture.js'" or similar. This is correct.

- [ ] **Step 8: Commit failing tests**

```bash
git add src/__tests__
git commit -m "test(capture): add failing tests for spawn wrapper covering success, timeout, error, crash, missing binary, unknown tool, schema validation"
```

---

### Task 9: Implement capture.ts to make tests pass

**Files:**
- Create: `src/capture.ts`

- [ ] **Step 1: Implement `src/capture.ts`**

```typescript
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
```

- [ ] **Step 2: Run tests**

Run: `pnpm test`
Expected: All 7 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/capture.ts
git commit -m "feat(server): implement Swift binary spawn wrapper with input validation and error mapping"
```

---

### Task 10: Implement MCP server entry point

**Files:**
- Create: `src/index.ts`

- [ ] **Step 1: Create `src/index.ts`**

```typescript
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
import type { ToolName } from "./types.js";

const server = new Server(
  { name: "deskview-mcp", version: "1.0.0" },
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
  return await runCapture(name as ToolName, args ?? {});
});

const transport = new StdioServerTransport();
await server.connect(transport);
process.stderr.write("deskview-mcp server connected\n");
```

- [ ] **Step 2: Compile**

Run: `pnpm build:server`
Expected: `server/index.js` exists. No TypeScript errors.

- [ ] **Step 3: Smoke-test the compiled server with a fake binary**

```bash
DESKVIEW_BIN="$PWD/src/__tests__/fixtures/stub-success.sh" \
  node -e '
    import("@modelcontextprotocol/sdk/client/index.js").then(async ({ Client }) => {
      const { StdioClientTransport } = await import("@modelcontextprotocol/sdk/client/stdio.js");
      const t = new StdioClientTransport({ command: "node", args: ["server/index.js"], env: { ...process.env } });
      const c = new Client({ name: "smoke", version: "0.0.0" }, { capabilities: {} });
      await c.connect(t);
      const tools = await c.listTools();
      console.log("TOOLS:", tools.tools.map(x => x.name).join(","));
      const r = await c.callTool({ name: "capture_desk_view", arguments: {} });
      console.log("CONTENT_TYPES:", r.content.map(x => x.type).join(","));
      await c.close();
    }).catch(e => { console.error(e); process.exit(1); });
  '
```

Expected output (modulo log noise):
```
TOOLS: capture_desk_view,capture_on_stable,capture_on_gesture
CONTENT_TYPES: image,text
```

- [ ] **Step 4: Commit**

```bash
git add src/index.ts
git commit -m "feat(server): wire MCP server with ListTools/CallTool handlers over stdio"
```

---

### Task 11: Run full test suite plus typecheck before packaging

**Files:** none (verification only)

- [ ] **Step 1: Run typecheck**

Run: `pnpm tsc --noEmit`
Expected: No errors.

- [ ] **Step 2: Run unit tests**

Run: `pnpm test`
Expected: 7 tests pass.

- [ ] **Step 3: Build full project (Swift + TS)**

Run: `pnpm build`
Expected: `bin/deskview-capture` exists. `server/index.js` exists.

- [ ] **Step 4: Run server end-to-end against the real (stub-output) Swift binary**

Run:
```bash
DESKVIEW_BIN="$PWD/bin/deskview-capture" node -e '
  import("@modelcontextprotocol/sdk/client/index.js").then(async ({ Client }) => {
    const { StdioClientTransport } = await import("@modelcontextprotocol/sdk/client/stdio.js");
    const t = new StdioClientTransport({ command: "node", args: ["server/index.js"], env: { ...process.env } });
    const c = new Client({ name: "smoke", version: "0.0.0" }, { capabilities: {} });
    await c.connect(t);
    const r = await c.callTool({ name: "capture_desk_view", arguments: {} });
    console.log(JSON.stringify({ isError: r.isError ?? false, types: r.content.map(x => x.type) }));
    await c.close();
  });
'
```

Expected: Prints `{"isError":false,"types":["image","text"]}` (image will be empty stub but content blocks are correct shape).

If it fails because the stub binary returns empty `image_base64`, that is a known artifact of Phase 1 stubs. Adjust the assertion in capture.ts only if Step 1 of Task 9 already covers it, otherwise note it and continue; real images arrive in Phase 4.

- [ ] **Step 5: No commit (verification only).**

---

# PHASE 3: First Bundle Install

### Task 12: Pack and install .mcpb in Claude Desktop

**Files:** none (operational task)

This task is performed by the human, not a subagent. Subagents should pause here and surface instructions.

- [ ] **Step 1: Pack the bundle**

Run: `pnpm package`
Expected: Produces `deskview-mcp-1.0.0.mcpb` in the repo root.

- [ ] **Step 2: Inspect bundle contents**

Run: `unzip -l deskview-mcp-1.0.0.mcpb | head -40`
Expected: Lists `manifest.json`, `package.json`, `server/index.js`, `bin/deskview-capture`, `node_modules/...`. Does NOT list `src/`, `swift/`, `tsconfig.json`, `pnpm-lock.yaml`.

- [ ] **Step 3: Install in Claude Desktop**

Manual: Settings → Extensions → Advanced settings → Extension Developer → Install Extension... → select `deskview-mcp-1.0.0.mcpb` → Confirm.

- [ ] **Step 4: Verify the three tools appear**

In a new Claude Desktop chat, ask: "What tools do you have available?" Confirm `capture_desk_view`, `capture_on_stable`, `capture_on_gesture` are listed.

- [ ] **Step 5: Call each tool and verify stub responses**

Each tool call should return a (currently empty) image content block plus a text block. Errors here usually mean: binary not executable, env var not resolved, or Node failed to start. Check the Extension Developer logs panel.

- [ ] **Step 6: Commit nothing (operational checkpoint).**

If anything is broken, fix and re-pack before proceeding.

---

# PHASE 4: Real `snapshot` Implementation

### Task 13: Implement DeskViewSession with two-tier device discovery

**Files:**
- Create: `swift/Sources/DeskviewCapture/DeskViewSession.swift`

- [ ] **Step 1: Create `DeskViewSession.swift`**

```swift
import Foundation
import AVFoundation

final class DeskViewSession {
    let session = AVCaptureSession()
    private(set) var device: AVCaptureDevice?
    private(set) var deviceName: String = "unknown"

    func discoverDevice() throws {
        // Tier 1: dedicated Desk View camera type.
        let primary = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.deskViewCamera],
            mediaType: .video,
            position: .unspecified
        )
        if let dv = primary.devices.first {
            self.device = dv
            self.deviceName = dv.localizedName
            logStderr("DeskViewSession: discovered primary device '\(dv.localizedName)'")
            return
        }

        // Tier 2: companion of a Continuity Camera.
        let fallback = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        if let main = fallback.devices.first,
           let companion = main.companionDeskViewCamera {
            self.device = companion
            self.deviceName = companion.localizedName
            logStderr("DeskViewSession: discovered fallback companion '\(companion.localizedName)' of '\(main.localizedName)'")
            return
        }

        throw DeskviewError.noDevice
    }

    func ensureCameraAuthorization() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .video) { ok in
                granted = ok
                sem.signal()
            }
            sem.wait()
            if !granted { throw DeskviewError.permissionDenied }
        case .denied, .restricted:
            throw DeskviewError.permissionDenied
        @unknown default:
            throw DeskviewError.permissionDenied
        }
    }

    func configureForStillCapture() throws -> AVCaptureVideoDataOutput {
        guard let device = device else { throw DeskviewError.noDevice }
        session.beginConfiguration()
        session.sessionPreset = .high

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            session.commitConfiguration()
            throw DeskviewError.captureFailed("AVCaptureDeviceInput init failed: \(error)")
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw DeskviewError.captureFailed("cannot add device input")
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw DeskviewError.captureFailed("cannot add video data output")
        }
        session.addOutput(output)

        session.commitConfiguration()
        return output
    }

    func start() { session.startRunning() }
    func stop() { session.stopRunning() }
}
```

- [ ] **Step 2: Build to confirm compilation**

Run: `pnpm build:swift`
Expected: Builds without errors. Stub subcommands still work.

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/DeskviewCapture/DeskViewSession.swift
git commit -m "feat(swift): add DeskViewSession with two-tier device discovery and authorization"
```

---

### Task 14: Implement ImageEncoder for CMSampleBuffer to PNG base64

**Files:**
- Create: `swift/Sources/DeskviewCapture/ImageEncoder.swift`

- [ ] **Step 1: Create `ImageEncoder.swift`**

```swift
import Foundation
import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import AppKit

enum ImageEncoder {
    static let context = CIContext(options: nil)

    static func pngBase64(from sampleBuffer: CMSampleBuffer) throws -> (base64: String, width: Int, height: Int) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw DeskviewError.captureFailed("no pixel buffer in sample")
        }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = Int(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int(CVPixelBufferGetHeight(pixelBuffer))

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw DeskviewError.captureFailed("CIContext.createCGImage failed")
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw DeskviewError.captureFailed("PNG encode failed")
        }
        return (base64: pngData.base64EncodedString(), width: width, height: height)
    }
}
```

- [ ] **Step 2: Build**

Run: `pnpm build:swift`
Expected: Builds without errors.

- [ ] **Step 3: Commit**

```bash
git add swift/Sources/DeskviewCapture/ImageEncoder.swift
git commit -m "feat(swift): add CMSampleBuffer to PNG base64 encoder"
```

---

### Task 15: Wire real snapshot capture

**Files:**
- Modify: `swift/Sources/DeskviewCapture/main.swift` (Snapshot subcommand)
- Create: `swift/Sources/DeskviewCapture/SnapshotCapturer.swift`

- [ ] **Step 1: Create `SnapshotCapturer.swift`**

```swift
import Foundation
import AVFoundation

final class SnapshotCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session: DeskViewSession
    private let semaphore = DispatchSemaphore(value: 0)
    private var captured: (base64: String, width: Int, height: Int)?
    private var captureError: DeskviewError?
    private var didCapture = false

    init(session: DeskViewSession) { self.session = session }

    func capture(timeoutMs: Int) throws -> (base64: String, width: Int, height: Int, deviceName: String, waitMs: Int) {
        let output = try session.configureForStillCapture()
        let queue = DispatchQueue(label: "deskview.capture")
        output.setSampleBufferDelegate(self, queue: queue)

        let start = Date()
        session.start()
        let deadline = DispatchTime.now() + .milliseconds(timeoutMs)
        let result = semaphore.wait(timeout: deadline)
        session.stop()

        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        if result == .timedOut {
            throw DeskviewError.captureFailed("no frame received within \(timeoutMs)ms")
        }
        if let err = captureError { throw err }
        guard let cap = captured else { throw DeskviewError.captureFailed("missing frame") }
        return (cap.base64, cap.width, cap.height, session.deviceName, elapsedMs)
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !didCapture else { return }
        didCapture = true
        do {
            captured = try ImageEncoder.pngBase64(from: sampleBuffer)
        } catch let err as DeskviewError {
            captureError = err
        } catch {
            captureError = .captureFailed("\(error)")
        }
        semaphore.signal()
    }
}
```

- [ ] **Step 2: Replace the Snapshot stub in `main.swift`**

Replace the existing `Snapshot.run()` body with:

```swift
    func run() throws {
        let session = DeskViewSession()
        do {
            try session.ensureCameraAuthorization()
            try session.discoverDevice()
            let capturer = SnapshotCapturer(session: session)
            let cap = try capturer.capture(timeoutMs: 5000)
            let metadata = CaptureMetadata(
                width: cap.width,
                height: cap.height,
                captured_at: ISO8601DateFormatter().string(from: Date()),
                wait_duration_ms: cap.waitMs,
                device_name: cap.deviceName
            )
            emit(CaptureResult.success(image: cap.base64, metadata: metadata))
        } catch let err as DeskviewError {
            logStderr("snapshot failed: \(err.message)")
            emit(CaptureResult.error(err))
        } catch {
            logStderr("snapshot unexpected error: \(error)")
            emit(CaptureResult.error(.internalError("\(error)")))
        }
    }
```

- [ ] **Step 3: Build**

Run: `pnpm build:swift`
Expected: Compiles without errors.

- [ ] **Step 4: Manually verify against real hardware**

Prerequisites: iPhone mounted, Desk View enabled.

Run: `./bin/deskview-capture snapshot | jq '{status, error_code, w: .metadata.width, h: .metadata.height, image_size: (.image_base64 | length)}'`

Expected (success): `{"status":"success","error_code":null,"w":<positive int>,"h":<positive int>,"image_size":<large number>}`. Save the base64 to a file and view it: `./bin/deskview-capture snapshot | jq -r .image_base64 | base64 -D > /tmp/snap.png && open /tmp/snap.png`. The image should show the desk.

Expected (no iPhone): `{"status":"error","error_code":"no_device", ...}`.

Expected (denied permission): `{"status":"error","error_code":"permission_denied", ...}`.

- [ ] **Step 5: Repackage and reinstall extension, test in Claude Desktop**

Run: `pnpm package`
Manual: Reinstall the .mcpb. Call `capture_desk_view` from a chat. Confirm an actual desk image returns.

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/DeskviewCapture/SnapshotCapturer.swift swift/Sources/DeskviewCapture/main.swift
git commit -m "feat(swift): implement real snapshot capture via AVCaptureVideoDataOutput"
```

---

### Task 16: Tighten snapshot error paths

**Files:** none (verification + minor tweaks if needed)

- [ ] **Step 1: Verify error_code strings match Section 6 spec**

Run with no iPhone: `./bin/deskview-capture snapshot | jq .error_code`
Expected: `"no_device"`.

If a different code surfaces, fix the mapping in `DeskviewError.swift`.

- [ ] **Step 2: Verify the Node side surfaces friendly text**

In Claude Desktop with no iPhone, call `capture_desk_view`. Confirm the user-facing text mentions Continuity Camera and Desk View enablement steps.

- [ ] **Step 3: Commit only if changes were needed.**

---

# PHASE 5: Real `stable` Implementation

### Task 17: Pure-function pixel-diff math with unit tests (TDD)

**Files:**
- Create: `swift/Tests/DeskviewCaptureTests/StableDetectorTests.swift`
- Create: `swift/Sources/DeskviewCapture/StableDetector.swift` (logic struct only at first)

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import DeskviewCapture

final class StableDetectorTests: XCTestCase {
    func testThresholdMappingByName() {
        XCTAssertEqual(StableDetector.threshold(for: "low"), 0.05, accuracy: 1e-9)
        XCTAssertEqual(StableDetector.threshold(for: "medium"), 0.02, accuracy: 1e-9)
        XCTAssertEqual(StableDetector.threshold(for: "high"), 0.005, accuracy: 1e-9)
    }

    func testThresholdDefaultsToMediumOnUnknown() {
        XCTAssertEqual(StableDetector.threshold(for: "asdf"), 0.02, accuracy: 1e-9)
    }

    func testMotionFractionAllSamePixels() {
        let a = [UInt8](repeating: 100, count: 64 * 48)
        let b = [UInt8](repeating: 100, count: 64 * 48)
        XCTAssertEqual(StableDetector.motionFraction(prev: a, curr: b, deltaThreshold: 15), 0.0)
    }

    func testMotionFractionAllChangedPixels() {
        let a = [UInt8](repeating: 0, count: 64 * 48)
        let b = [UInt8](repeating: 200, count: 64 * 48)
        XCTAssertEqual(StableDetector.motionFraction(prev: a, curr: b, deltaThreshold: 15), 1.0)
    }

    func testMotionFractionIgnoresChangesBelowThreshold() {
        // 14 < 15 threshold, so zero pixels count as motion.
        let a = [UInt8](repeating: 0, count: 64 * 48)
        let b = [UInt8](repeating: 14, count: 64 * 48)
        XCTAssertEqual(StableDetector.motionFraction(prev: a, curr: b, deltaThreshold: 15), 0.0)
    }

    func testMotionFractionHalfChanged() {
        var a = [UInt8](repeating: 0, count: 64 * 48)
        var b = [UInt8](repeating: 0, count: 64 * 48)
        for i in 0..<(64 * 48 / 2) {
            b[i] = 200
        }
        XCTAssertEqual(StableDetector.motionFraction(prev: a, curr: b, deltaThreshold: 15), 0.5, accuracy: 0.001)
    }

    func testStabilityCounterIncrementsBelowThresholdAndResetsAbove() {
        var counter = StableDetector.StabilityCounter()
        XCTAssertEqual(counter.update(motion: 0.01, threshold: 0.02), 1)
        XCTAssertEqual(counter.update(motion: 0.005, threshold: 0.02), 2)
        XCTAssertEqual(counter.update(motion: 0.10, threshold: 0.02), 0)
        XCTAssertEqual(counter.update(motion: 0.0, threshold: 0.02), 1)
    }
}
```

- [ ] **Step 2: Create `StableDetector.swift` with just the pure math (no AVFoundation yet)**

```swift
import Foundation

enum StableDetector {
    static let downsampledWidth = 64
    static let downsampledHeight = 48
    static let totalPixels = downsampledWidth * downsampledHeight

    static func threshold(for sensitivity: String) -> Double {
        switch sensitivity {
        case "low": return 0.05
        case "high": return 0.005
        default: return 0.02
        }
    }

    static func motionFraction(prev: [UInt8], curr: [UInt8], deltaThreshold: Int) -> Double {
        precondition(prev.count == curr.count)
        var count = 0
        let n = prev.count
        for i in 0..<n {
            let d = Int(prev[i]) - Int(curr[i])
            if abs(d) > deltaThreshold { count += 1 }
        }
        return Double(count) / Double(n)
    }

    struct StabilityCounter {
        private(set) var consecutive = 0
        @discardableResult
        mutating func update(motion: Double, threshold: Double) -> Int {
            if motion <= threshold {
                consecutive += 1
            } else {
                consecutive = 0
            }
            return consecutive
        }
    }
}
```

- [ ] **Step 3: Run tests**

Run: `cd swift && swift test`
Expected: All StableDetector tests pass plus the existing smoke tests.

- [ ] **Step 4: Commit**

```bash
git add swift/Sources/DeskviewCapture/StableDetector.swift swift/Tests/DeskviewCaptureTests/StableDetectorTests.swift
git commit -m "feat(swift): add pure pixel-diff motion math with unit tests"
```

---

### Task 18: Wire stable subcommand to the AV pipeline

**Files:**
- Modify: `swift/Sources/DeskviewCapture/StableDetector.swift` (add AV integration)
- Modify: `swift/Sources/DeskviewCapture/main.swift` (Stable subcommand)
- Create: `swift/Sources/DeskviewCapture/StableCapturer.swift`

- [ ] **Step 1: Create `StableCapturer.swift`**

```swift
import Foundation
import AVFoundation
import CoreImage

final class StableCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session: DeskViewSession
    private let stabilityDurationMs: Int
    private let timeoutMs: Int
    private let threshold: Double
    private let frameIntervalMs: Int = 100  // 10fps

    private let semaphore = DispatchSemaphore(value: 0)
    private var counter = StableDetector.StabilityCounter()
    private var prevDownsampled: [UInt8]?
    private var lastFullFrame: (base64: String, w: Int, h: Int)?
    private var pendingResult: (base64: String, w: Int, h: Int, status: String)?
    private var captureError: DeskviewError?
    private let started = Date()
    private let ciContext = CIContext(options: nil)

    init(session: DeskViewSession, stabilityDurationMs: Int, timeoutMs: Int, sensitivity: String) {
        self.session = session
        self.stabilityDurationMs = stabilityDurationMs
        self.timeoutMs = timeoutMs
        self.threshold = StableDetector.threshold(for: sensitivity)
    }

    func run() throws -> (base64: String, w: Int, h: Int, status: String, waitMs: Int, deviceName: String) {
        let output = try session.configureForStillCapture()
        let queue = DispatchQueue(label: "deskview.stable")
        output.setSampleBufferDelegate(self, queue: queue)
        session.start()

        let deadline = DispatchTime.now() + .milliseconds(timeoutMs + 500)
        _ = semaphore.wait(timeout: deadline)
        session.stop()

        let waitMs = Int(Date().timeIntervalSince(started) * 1000)
        if let err = captureError { throw err }

        if let p = pendingResult {
            return (p.base64, p.w, p.h, p.status, waitMs, session.deviceName)
        }
        // Hard timeout: surface last frame if any, else error.
        if let f = lastFullFrame {
            return (f.base64, f.w, f.h, "timeout", waitMs, session.deviceName)
        }
        throw DeskviewError.timeout
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard pendingResult == nil else { return }

        // Always keep the most recent full-resolution frame for fallback.
        if let png = try? ImageEncoder.pngBase64(from: sampleBuffer) {
            lastFullFrame = (png.base64, png.width, png.height)
        }

        // Compute downsampled grayscale buffer for diff.
        guard let curr = downsampledLuma(from: sampleBuffer) else { return }

        if let prev = prevDownsampled {
            let motion = StableDetector.motionFraction(prev: prev, curr: curr, deltaThreshold: 15)
            let consec = counter.update(motion: motion, threshold: threshold)
            let stableMs = consec * frameIntervalMs
            logStderr("stable: motion=\(String(format: "%.4f", motion)) stableMs=\(stableMs)")
            if stableMs >= stabilityDurationMs, let f = lastFullFrame {
                pendingResult = (f.base64, f.w, f.h, "success")
                semaphore.signal()
            }
        }
        prevDownsampled = curr

        // Deadline check.
        if Int(Date().timeIntervalSince(started) * 1000) >= timeoutMs {
            if let f = lastFullFrame {
                pendingResult = (f.base64, f.w, f.h, "timeout")
            }
            semaphore.signal()
        }
    }

    private func downsampledLuma(from sampleBuffer: CMSampleBuffer) -> [UInt8]? {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        let ci = CIImage(cvPixelBuffer: pb)
        let scaleX = Double(StableDetector.downsampledWidth) / Double(ci.extent.width)
        let scaleY = Double(StableDetector.downsampledHeight) / Double(ci.extent.height)
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        var bytes = [UInt8](repeating: 0,
                            count: StableDetector.downsampledWidth * StableDetector.downsampledHeight * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        ciContext.render(scaled,
                         toBitmap: &bytes,
                         rowBytes: StableDetector.downsampledWidth * 4,
                         bounds: CGRect(x: 0, y: 0,
                                        width: StableDetector.downsampledWidth,
                                        height: StableDetector.downsampledHeight),
                         format: .BGRA8,
                         colorSpace: cs)
        var luma = [UInt8](repeating: 0, count: StableDetector.totalPixels)
        for i in 0..<StableDetector.totalPixels {
            let b = Double(bytes[i * 4 + 0])
            let g = Double(bytes[i * 4 + 1])
            let r = Double(bytes[i * 4 + 2])
            luma[i] = UInt8(min(255.0, 0.299 * r + 0.587 * g + 0.114 * b))
        }
        return luma
    }
}
```

- [ ] **Step 2: Replace `Stable.run()` in `main.swift`**

```swift
    func run() throws {
        let session = DeskViewSession()
        do {
            try session.ensureCameraAuthorization()
            try session.discoverDevice()
            let cap = StableCapturer(
                session: session,
                stabilityDurationMs: duration,
                timeoutMs: timeout,
                sensitivity: sensitivity
            )
            let r = try cap.run()
            let metadata = CaptureMetadata(
                width: r.w, height: r.h,
                captured_at: ISO8601DateFormatter().string(from: Date()),
                wait_duration_ms: r.waitMs,
                device_name: r.deviceName
            )
            if r.status == "success" {
                emit(CaptureResult.success(image: r.base64, metadata: metadata))
            } else {
                emit(CaptureResult.timeout(image: r.base64, metadata: metadata))
            }
        } catch let err as DeskviewError {
            logStderr("stable failed: \(err.message)")
            emit(CaptureResult.error(err))
        } catch {
            logStderr("stable unexpected error: \(error)")
            emit(CaptureResult.error(.internalError("\(error)")))
        }
    }
```

- [ ] **Step 3: Build**

Run: `pnpm build:swift`
Expected: No errors.

- [ ] **Step 4: Manually verify behavior**

```bash
# With desk in motion, expect timeout after 5s.
./bin/deskview-capture stable --duration 1000 --timeout 5000 --sensitivity medium | jq '{status, wait: .metadata.wait_duration_ms}'

# With still desk, expect success after ~1.2s.
./bin/deskview-capture stable --duration 1000 --timeout 30000 --sensitivity medium | jq '{status, wait: .metadata.wait_duration_ms}'
```

Expected: First call eventually returns `{"status":"timeout"}`. Second call returns `{"status":"success", "wait": <about 1000-2000>}`.

- [ ] **Step 5: Repackage, reinstall, test in Claude Desktop**

Run: `pnpm package`
Manual: Reinstall, call `capture_on_stable` from a chat with various movement patterns.

- [ ] **Step 6: Commit**

```bash
git add swift/Sources/DeskviewCapture/StableCapturer.swift swift/Sources/DeskviewCapture/main.swift
git commit -m "feat(swift): wire stable subcommand to AV pipeline with downsampled luma diff"
```

---

### Task 19: Tune sensitivity thresholds against real footage

**Files:** none (calibration)

- [ ] **Step 1: With normal desk lighting, hold a still posture and run with each sensitivity**

```bash
for s in low medium high; do
  echo "=== $s ==="
  ./bin/deskview-capture stable --duration 1500 --timeout 15000 --sensitivity $s | jq '{status, wait: .metadata.wait_duration_ms}'
done
```

Expected: All three reach `success` within reasonable time on a still scene. `high` should be the most likely to time out if there is fan-induced shimmer.

- [ ] **Step 2: With deliberate hand motion, verify sensitivity differences**

Move a hand briefly (say, 1 second), then hold still. Run each sensitivity and confirm motion is detected correctly: `low` is most forgiving, `high` is twitchy. If the thresholds feel off in practice, adjust the constants in `StableDetector.threshold(for:)` and re-run unit tests + retest. Update PRD-traceable comments only if needed.

- [ ] **Step 3: Commit only if thresholds were adjusted.**

---

# PHASE 6: Real `gesture` Implementation

### Task 20: Pure-function gesture classifiers with unit tests (TDD)

**Files:**
- Create: `swift/Tests/DeskviewCaptureTests/GestureClassifierTests.swift`
- Create: `swift/Sources/DeskviewCapture/GestureDetector.swift` (classifier types only)

- [ ] **Step 1: Define a landmark-key abstraction for testing**

The Vision framework returns `[VNHumanHandPoseObservation.JointName: VNRecognizedPoint]`. For unit tests, we use a parallel pure-Swift type and test the math directly. The detector wraps Vision and converts to this type.

- [ ] **Step 2: Create `GestureDetector.swift` with classifier surface**

```swift
import Foundation
import CoreGraphics

enum HandJoint: String {
    case thumbTip, thumbMCP
    case indexTip, indexPIP, indexMCP
    case middleTip, middlePIP, middleMCP
    case ringTip, ringPIP, ringMCP
    case pinkyTip, pinkyPIP, pinkyMCP
}

typealias HandLandmarks = [HandJoint: CGPoint]

enum GestureKind: String {
    case thumbsUp = "thumbs_up"
    case peace
    case okSign = "ok_sign"
    case fist
    case openPalm = "open_palm"
}

enum GestureClassifier {
    // Vision uses top-of-image origin; "above" means smaller y (rising on screen).
    // We treat smaller y as "higher".
    static func isAbove(_ a: CGPoint, _ b: CGPoint) -> Bool { a.y < b.y }
    static func isBelow(_ a: CGPoint, _ b: CGPoint) -> Bool { a.y > b.y }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return sqrt(Double(dx * dx + dy * dy))
    }

    static func matches(_ kind: GestureKind, landmarks lm: HandLandmarks) -> Bool {
        switch kind {
        case .thumbsUp:
            guard let tT = lm[.thumbTip], let tM = lm[.thumbMCP],
                  let iT = lm[.indexTip], let iP = lm[.indexPIP],
                  let mT = lm[.middleTip], let mP = lm[.middlePIP],
                  let rT = lm[.ringTip], let rP = lm[.ringPIP],
                  let pT = lm[.pinkyTip], let pP = lm[.pinkyPIP] else { return false }
            return isAbove(tT, tM)
                && isBelow(iT, iP) && isBelow(mT, mP) && isBelow(rT, rP) && isBelow(pT, pP)
        case .peace:
            guard let iT = lm[.indexTip], let iP = lm[.indexPIP],
                  let mT = lm[.middleTip], let mP = lm[.middlePIP],
                  let rT = lm[.ringTip], let rP = lm[.ringPIP],
                  let pT = lm[.pinkyTip], let pP = lm[.pinkyPIP] else { return false }
            return isAbove(iT, iP) && isAbove(mT, mP) && isBelow(rT, rP) && isBelow(pT, pP)
        case .okSign:
            guard let tT = lm[.thumbTip], let iT = lm[.indexTip],
                  let mT = lm[.middleTip], let mP = lm[.middlePIP],
                  let rT = lm[.ringTip], let rP = lm[.ringPIP],
                  let pT = lm[.pinkyTip], let pP = lm[.pinkyPIP] else { return false }
            // 30 normalized units in the PRD: Vision returns 0..1, so 30 of 1000 is 0.03.
            return distance(tT, iT) < 0.03
                && isAbove(mT, mP) && isAbove(rT, rP) && isAbove(pT, pP)
        case .fist:
            guard let tT = lm[.thumbTip], let tM = lm[.thumbMCP],
                  let iT = lm[.indexTip], let iM = lm[.indexMCP],
                  let mT = lm[.middleTip], let mM = lm[.middleMCP],
                  let rT = lm[.ringTip], let rM = lm[.ringMCP],
                  let pT = lm[.pinkyTip], let pM = lm[.pinkyMCP] else { return false }
            return isBelow(tT, tM) && isBelow(iT, iM) && isBelow(mT, mM)
                && isBelow(rT, rM) && isBelow(pT, pM)
        case .openPalm:
            guard let tT = lm[.thumbTip], let iP = lm[.indexPIP],
                  let iT = lm[.indexTip],
                  let mT = lm[.middleTip], let mP = lm[.middlePIP],
                  let rT = lm[.ringTip], let rP = lm[.ringPIP],
                  let pT = lm[.pinkyTip], let pP = lm[.pinkyPIP] else { return false }
            // Thumb has no PIP; require it above index PIP (a reasonable proxy for spread palm).
            return isAbove(tT, iP) && isAbove(iT, iP) && isAbove(mT, mP)
                && isAbove(rT, rP) && isAbove(pT, pP)
        }
    }

    struct HoldCounter {
        private(set) var consecutive = 0
        @discardableResult
        mutating func update(matched: Bool) -> Int {
            consecutive = matched ? consecutive + 1 : 0
            return consecutive
        }
    }
}
```

- [ ] **Step 3: Create `swift/Tests/DeskviewCaptureTests/GestureClassifierTests.swift`**

```swift
import XCTest
@testable import DeskviewCapture
import CoreGraphics

final class GestureClassifierTests: XCTestCase {
    // Helper: y in Vision = top-of-image origin. "Above" means smaller y.
    private func at(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    private func thumbsUpLandmarks() -> HandLandmarks {
        // Thumb high, all other tips low.
        return [
            .thumbTip: at(0.5, 0.1), .thumbMCP: at(0.5, 0.4),
            .indexTip: at(0.55, 0.7), .indexPIP: at(0.55, 0.5), .indexMCP: at(0.55, 0.4),
            .middleTip: at(0.5, 0.7), .middlePIP: at(0.5, 0.5), .middleMCP: at(0.5, 0.4),
            .ringTip: at(0.45, 0.7), .ringPIP: at(0.45, 0.5), .ringMCP: at(0.45, 0.4),
            .pinkyTip: at(0.4, 0.7), .pinkyPIP: at(0.4, 0.5), .pinkyMCP: at(0.4, 0.4),
        ]
    }

    func testThumbsUpMatchesItself() {
        XCTAssertTrue(GestureClassifier.matches(.thumbsUp, landmarks: thumbsUpLandmarks()))
    }

    func testThumbsUpRejectsThumbDown() {
        var lm = thumbsUpLandmarks()
        lm[.thumbTip] = at(0.5, 0.6) // thumb tip below MCP
        XCTAssertFalse(GestureClassifier.matches(.thumbsUp, landmarks: lm))
    }

    func testThumbsUpRejectsIndexUp() {
        var lm = thumbsUpLandmarks()
        lm[.indexTip] = at(0.55, 0.3) // index above its PIP
        XCTAssertFalse(GestureClassifier.matches(.thumbsUp, landmarks: lm))
    }

    func testPeace() {
        let lm: HandLandmarks = [
            .indexTip: at(0.5, 0.1), .indexPIP: at(0.5, 0.4),
            .middleTip: at(0.55, 0.1), .middlePIP: at(0.55, 0.4),
            .ringTip: at(0.6, 0.7), .ringPIP: at(0.6, 0.5),
            .pinkyTip: at(0.65, 0.7), .pinkyPIP: at(0.65, 0.5),
        ]
        XCTAssertTrue(GestureClassifier.matches(.peace, landmarks: lm))
    }

    func testOkSignNeedsCloseThumbAndIndex() {
        var lm: HandLandmarks = [
            .thumbTip: at(0.50, 0.50),
            .indexTip: at(0.51, 0.51),
            .middleTip: at(0.55, 0.10), .middlePIP: at(0.55, 0.40),
            .ringTip: at(0.60, 0.10), .ringPIP: at(0.60, 0.40),
            .pinkyTip: at(0.65, 0.10), .pinkyPIP: at(0.65, 0.40),
        ]
        XCTAssertTrue(GestureClassifier.matches(.okSign, landmarks: lm))

        lm[.indexTip] = at(0.80, 0.80)
        XCTAssertFalse(GestureClassifier.matches(.okSign, landmarks: lm))
    }

    func testFist() {
        let lm: HandLandmarks = [
            .thumbTip: at(0.50, 0.60), .thumbMCP: at(0.50, 0.40),
            .indexTip: at(0.55, 0.60), .indexMCP: at(0.55, 0.40),
            .middleTip: at(0.50, 0.60), .middleMCP: at(0.50, 0.40),
            .ringTip: at(0.45, 0.60), .ringMCP: at(0.45, 0.40),
            .pinkyTip: at(0.40, 0.60), .pinkyMCP: at(0.40, 0.40),
        ]
        XCTAssertTrue(GestureClassifier.matches(.fist, landmarks: lm))
    }

    func testOpenPalm() {
        let lm: HandLandmarks = [
            .thumbTip: at(0.30, 0.10),
            .indexTip: at(0.50, 0.10), .indexPIP: at(0.50, 0.40),
            .middleTip: at(0.55, 0.10), .middlePIP: at(0.55, 0.40),
            .ringTip: at(0.60, 0.10), .ringPIP: at(0.60, 0.40),
            .pinkyTip: at(0.65, 0.10), .pinkyPIP: at(0.65, 0.40),
        ]
        XCTAssertTrue(GestureClassifier.matches(.openPalm, landmarks: lm))
    }

    func testMissingLandmarksReturnsFalse() {
        let lm: HandLandmarks = [.thumbTip: at(0, 0)]
        for kind in [GestureKind.thumbsUp, .peace, .okSign, .fist, .openPalm] {
            XCTAssertFalse(GestureClassifier.matches(kind, landmarks: lm), "\(kind) should fail on partial data")
        }
    }

    func testHoldCounterIncrementsAndResets() {
        var c = GestureClassifier.HoldCounter()
        XCTAssertEqual(c.update(matched: true), 1)
        XCTAssertEqual(c.update(matched: true), 2)
        XCTAssertEqual(c.update(matched: false), 0)
        XCTAssertEqual(c.update(matched: true), 1)
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd swift && swift test`
Expected: All gesture classifier tests pass alongside existing tests.

- [ ] **Step 5: Commit**

```bash
git add swift/Sources/DeskviewCapture/GestureDetector.swift swift/Tests/DeskviewCaptureTests/GestureClassifierTests.swift
git commit -m "feat(swift): add pure gesture classifier with unit tests for all five gestures"
```

---

### Task 21: Wire gesture subcommand to Vision

**Files:**
- Create: `swift/Sources/DeskviewCapture/GestureCapturer.swift`
- Modify: `swift/Sources/DeskviewCapture/main.swift` (Gesture subcommand)

- [ ] **Step 1: Create `GestureCapturer.swift`**

```swift
import Foundation
import AVFoundation
import Vision

final class GestureCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session: DeskViewSession
    private let kind: GestureKind
    private let holdMs: Int
    private let timeoutMs: Int
    private let frameIntervalMs: Int = 67  // ~15fps

    private var holdCounter = GestureClassifier.HoldCounter()
    private let semaphore = DispatchSemaphore(value: 0)
    private var pendingResult: (base64: String, w: Int, h: Int, status: String)?
    private var captureError: DeskviewError?
    private let started = Date()
    private var lastFullFrame: (base64: String, w: Int, h: Int)?

    init(session: DeskViewSession, kind: GestureKind, holdMs: Int, timeoutMs: Int) {
        self.session = session
        self.kind = kind
        self.holdMs = holdMs
        self.timeoutMs = timeoutMs
    }

    func run() throws -> (base64: String, w: Int, h: Int, status: String, waitMs: Int, deviceName: String) {
        let output = try session.configureForStillCapture()
        let queue = DispatchQueue(label: "deskview.gesture")
        output.setSampleBufferDelegate(self, queue: queue)
        session.start()

        let deadline = DispatchTime.now() + .milliseconds(timeoutMs + 500)
        _ = semaphore.wait(timeout: deadline)
        session.stop()

        let waitMs = Int(Date().timeIntervalSince(started) * 1000)
        if let err = captureError { throw err }
        if let p = pendingResult { return (p.base64, p.w, p.h, p.status, waitMs, session.deviceName) }
        throw DeskviewError.timeout
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard pendingResult == nil else { return }

        if let png = try? ImageEncoder.pngBase64(from: sampleBuffer) {
            lastFullFrame = (png.base64, png.width, png.height)
        }

        // Run hand pose request synchronously on this frame.
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logStderr("gesture: vision error: \(error)")
            return
        }

        let matched: Bool
        if let observation = request.results?.first {
            let landmarks = mapLandmarks(observation: observation)
            matched = GestureClassifier.matches(kind, landmarks: landmarks)
        } else {
            matched = false
        }

        let consec = holdCounter.update(matched: matched)
        let heldMs = consec * frameIntervalMs
        if heldMs >= holdMs, let f = lastFullFrame {
            pendingResult = (f.base64, f.w, f.h, "success")
            semaphore.signal()
            return
        }

        if Int(Date().timeIntervalSince(started) * 1000) >= timeoutMs {
            // Gesture timeout per PRD returns isError, no frame.
            captureError = .timeout
            semaphore.signal()
        }
    }

    private func mapLandmarks(observation: VNHumanHandPoseObservation) -> HandLandmarks {
        var out = HandLandmarks()
        let mapping: [(HandJoint, VNHumanHandPoseObservation.JointName)] = [
            (.thumbTip, .thumbTip), (.thumbMCP, .thumbMP),
            (.indexTip, .indexTip), (.indexPIP, .indexPIP), (.indexMCP, .indexMCP),
            (.middleTip, .middleTip), (.middlePIP, .middlePIP), (.middleMCP, .middleMCP),
            (.ringTip, .ringTip), (.ringPIP, .ringPIP), (.ringMCP, .ringMCP),
            (.pinkyTip, .littleTip), (.pinkyPIP, .littlePIP), (.pinkyMCP, .littleMCP),
        ]
        for (ours, theirs) in mapping {
            if let p = try? observation.recognizedPoint(theirs), p.confidence > 0.3 {
                out[ours] = CGPoint(x: p.location.x, y: 1.0 - p.location.y)
            }
        }
        return out
    }
}
```

Note: Vision returns landmark `y` with bottom-of-image origin (mathematical convention), so we flip to top-of-image origin to match the classifier's "above means smaller y" convention.

- [ ] **Step 2: Replace `Gesture.run()` in `main.swift`**

```swift
    func run() throws {
        guard let kind = GestureKind(rawValue: type) else {
            emit(CaptureResult.error(.internalError("unknown gesture type: \(type)")))
            return
        }
        let session = DeskViewSession()
        do {
            try session.ensureCameraAuthorization()
            try session.discoverDevice()
            let cap = GestureCapturer(session: session, kind: kind, holdMs: hold, timeoutMs: timeout)
            let r = try cap.run()
            let metadata = CaptureMetadata(
                width: r.w, height: r.h,
                captured_at: ISO8601DateFormatter().string(from: Date()),
                wait_duration_ms: r.waitMs,
                device_name: r.deviceName
            )
            emit(CaptureResult.success(image: r.base64, metadata: metadata))
        } catch DeskviewError.timeout {
            logStderr("gesture: timeout reached")
            emit(CaptureResult.error(.timeout))
        } catch let err as DeskviewError {
            logStderr("gesture failed: \(err.message)")
            emit(CaptureResult.error(err))
        } catch {
            logStderr("gesture unexpected error: \(error)")
            emit(CaptureResult.error(.internalError("\(error)")))
        }
    }
```

- [ ] **Step 3: Build**

Run: `pnpm build:swift`
Expected: No errors.

- [ ] **Step 4: Manually verify each gesture**

```bash
for g in thumbs_up peace ok_sign fist open_palm; do
  echo "--- $g ---"
  ./bin/deskview-capture gesture --type $g --hold 400 --timeout 15000 | jq '{status, error_code}'
done
```

For each, hold the gesture in front of the desk camera. Expected: `{"status":"success","error_code":null}` within ~1s of holding the pose.

- [ ] **Step 5: Verify timeout path**

Run: `./bin/deskview-capture gesture --type thumbs_up --hold 500 --timeout 3000 | jq '{status, error_code}'`
Without showing the gesture, expected: `{"status":"error","error_code":"timeout"}`.

- [ ] **Step 6: Repackage, reinstall, test in Claude Desktop**

Run: `pnpm package`
Manual: Reinstall, exercise `capture_on_gesture` from a chat.

- [ ] **Step 7: Commit**

```bash
git add swift/Sources/DeskviewCapture/GestureCapturer.swift swift/Sources/DeskviewCapture/main.swift
git commit -m "feat(swift): wire gesture subcommand to Vision hand pose detection"
```

---

### Task 22: Verify Node side surfaces gesture timeout as isError text

**Files:** none (verification)

- [ ] **Step 1: Confirm capture.ts maps `error_code: "timeout"` to a useful user message**

Re-read the gesture timeout code path in `mapResult` of `src/capture.ts`. The Swift side returns `status: "error"` with `error_code: "timeout"` per PRD §5.3. This maps via `errorResponse(r.error_message ...)`. Confirm the message text mentions the gesture and timeout.

If the error message from Swift does not mention the requested gesture, add it. Edit `Gesture.run()` so the timeout error includes context: `emit(CaptureResult.error(.captureFailed("Gesture '\(type)' not detected within \(timeout)ms.")))` or similar (adjust DeskviewError accordingly).

- [ ] **Step 2: Test from Claude Desktop**

Call `capture_on_gesture` with `gesture: "thumbs_up"` and `timeout_ms: 3000`, hide your hand, confirm Claude reports a clear failure.

- [ ] **Step 3: Commit if changes were needed.**

---

# PHASE 7: QA & Polish

### Task 23: Execute manual test matrix from PRD §10

**Files:** none (QA)

- [ ] **Step 1: Run each scenario and record results**

Use the table from PRD Section 10. For each row, perform the action, capture observed behavior, mark pass/fail.

| Scenario | Pass criteria |
|---|---|
| No iPhone connected, call `capture_desk_view` | `isError` text mentions Continuity Camera + Desk View enable steps |
| Camera permission denied on first call | `isError` text references System Settings privacy pane |
| Permissions granted, Desk View active, `capture_desk_view` | image returned within 2s, sane resolution |
| `capture_on_stable` with active motion | blocks; on stop returns frame within (duration + 500ms) |
| `capture_on_stable` `timeout_ms: 5000` continuous motion | returns last frame with timeout note |
| `capture_on_gesture` `thumbs_up`, no gesture | blocks for full timeout, returns isError |
| `capture_on_gesture` brief flash under hold_duration_ms | keeps waiting (debounce) |
| `capture_on_gesture` thumbs up held 1s | returns frame within 500ms of gesture appearing |
| Each of 5 gesture types under good lighting | detected reliably |
| `capture_desk_view` x10 in quick succession | all complete, no zombie processes (check `pgrep deskview-capture` after each) |

- [ ] **Step 2: Fix anything that fails before proceeding**

If any scenario fails, file it as a fix-up task, address it, re-pack, re-test.

- [ ] **Step 3: Commit nothing for the QA itself; commits flow from any fix-ups.**

---

### Task 24: Write the README and produce icon.png

**Files:**
- Modify: `README.md`
- Create: `icon.png`

- [ ] **Step 1: Expand README to cover install, prerequisites, usage, troubleshooting**

```markdown
# Deskview MCP

A Claude Desktop Extension that gives Claude direct access to the iPhone Continuity Camera Desk View. Claude can grab one frame, wait for the scene to settle, or wait for a hand gesture before capturing.

## Tools

- `capture_desk_view` — grab one frame right now.
- `capture_on_stable` — wait until motion stops, then grab.
- `capture_on_gesture` — wait until a hand gesture is held, then grab.

All detection runs on-device. Wait operations cost zero tokens until the actual frame is delivered.

## Requirements

- macOS 13 (Ventura) or later, Apple Silicon (arm64). Intel is not supported in v1.
- iPhone running iOS 16 or later, signed into the same iCloud account as the Mac.
- Bluetooth and Wi-Fi enabled on both devices.
- Desk View enabled in Mac Control Center.
- iPhone mounted above the desk (Belkin MagSafe Continuity Camera mount or equivalent).

## Install

1. Download the latest `deskview-mcp-X.Y.Z.mcpb` from Releases.
2. Open Claude Desktop.
3. Settings, Extensions, Advanced settings, Extension Developer.
4. Click "Install Extension..." and select the .mcpb file.
5. Confirm install. The three tools appear in the next chat.

## First-run permissions

The first time any tool runs, macOS shows a camera permission prompt. Grant access. If you accidentally deny, fix it under System Settings, Privacy and Security, Camera. There is no programmatic re-prompt.

## Build from source

Requires pnpm 8+ and Swift 5.9+.

\`\`\`bash
pnpm install
pnpm build       # builds Swift binary + TypeScript server
pnpm package     # produces deskview-mcp-X.Y.Z.mcpb
\`\`\`

## Troubleshooting

- "No Desk View camera found": confirm iPhone is connected via Continuity Camera and Desk View is enabled in Control Center.
- "Camera permission denied": System Settings, Privacy and Security, Camera, enable Claude Desktop.
- Tools work in Terminal but not Claude Desktop: check Extension Developer logs panel for stderr output from the Swift binary.

## License

MIT.
```

- [ ] **Step 2: Produce icon.png (256x256)**

Easiest path: use a simple desk-and-camera glyph. If no graphic asset is available, generate a placeholder programmatically using `sips` or copy from an existing public-domain icon. Manually verify it is 256x256:

Run: `sips -g pixelWidth -g pixelHeight icon.png`
Expected: 256x256.

- [ ] **Step 3: Repack and confirm icon shows in Claude Desktop**

Run: `pnpm package`
Reinstall the .mcpb. Confirm the icon appears in the Extensions list.

- [ ] **Step 4: Commit**

```bash
git add README.md icon.png
git commit -m "docs: add user-facing README and extension icon"
```

---

### Task 25: Tag v1.0.0 and cut a GitHub release

**Files:** none (git operations)

- [ ] **Step 1: Final clean build**

```bash
pnpm clean
pnpm install
pnpm test
pnpm package
```

Expected: Tests pass. `deskview-mcp-1.0.0.mcpb` produced.

- [ ] **Step 2: Verify bundle one more time**

Run: `unzip -l deskview-mcp-1.0.0.mcpb`
Expected: includes `manifest.json`, `package.json`, `server/index.js`, `bin/deskview-capture`, `node_modules/`. Excludes `src/`, `swift/`, `tsconfig.json`, `pnpm-lock.yaml`.

- [ ] **Step 3: Tag and push**

Confirm with the user before pushing tags. After confirmation:

```bash
git tag v1.0.0
git push origin main --tags
```

- [ ] **Step 4: Create GitHub release with the .mcpb attached**

Confirm with the user before running. After confirmation:

```bash
gh release create v1.0.0 deskview-mcp-1.0.0.mcpb \
  --title "v1.0.0" \
  --notes "Initial release. Three MCP tools for capturing iPhone Continuity Camera Desk View frames: instant, on-stable, on-gesture. macOS 13+ Apple Silicon."
```

- [ ] **Step 5: No further commits.**

---

## Post-Plan Notes for Subagents

**When dispatched as a sonnet[1m] subagent for any task above, you must:**

1. Treat the task as self-contained: read only the files listed under **Files**, run only the commands listed in steps, and stop after the commit step.
2. Use `pnpm`, never `npm` or `yarn`. If you find yourself reaching for `npm`, abort and report.
3. Honor the no-em-dash rule in all written content.
4. If a step's command output does not match its expected output, stop and report the discrepancy. Do not silently work around it.
5. Camera-dependent manual verification steps (Phases 4-7) cannot be performed by a subagent without hardware. Surface a clear "manual verification needed" message and pause for the human.
6. After committing, return a brief summary of what changed and which step you stopped at.
