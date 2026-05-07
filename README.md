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

```bash
pnpm install
pnpm build
pnpm package
```
