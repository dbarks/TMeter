# TMeter

TMeter is a native macOS context and token meter for local ChatGPT Codex and Work sessions and Claude Work sessions.

The app shows current context usage, processed session tokens, short-window usage, and weekly usage. Values refresh every 15 seconds in the app window, menu bar, and Dock tile.

## Features

- Native SwiftUI interface with light and dark appearances
- ChatGPT Codex and Work context usage
- Claude Work context usage
- Short and weekly usage meters when local records provide them
- Menu bar and Dock status
- Optional 200K or 1M Claude context limit
- Native Open at Login support
- No network requests or analytics

## Requirements

- macOS 14 or later
- Apple Silicon Mac
- Xcode command-line tools for source builds
- ChatGPT Codex or Work sessions, Claude Work sessions, or both

## Build

```sh
chmod +x build.sh
./build.sh
open "dist/TMeter.app"
```

The build script creates an ad-hoc signed application at `dist/TMeter.app`.

## Install and open at login

Move `TMeter.app` into `/Applications`, then launch it. Open **Sources & preferences** and leave **Open TMeter at login** enabled.

macOS might require approval under **System Settings > General > Login Items & Extensions**.

## Local data sources

TMeter reads usage fields from local application records:

- ChatGPT Codex and Work session JSONL files under `~/.codex/sessions`
- Claude Work session records and `plan-usage-history.json` under Claude's Application Support folder

Standard Chat conversations do not expose a supported local token feed. TMeter does not decrypt application storage, display message content, store credentials, or transmit data.

Claude's local session records do not include the active context-window limit. Choose 200K or 1M in the app to match your model and plan.

## Tests

```sh
mkdir -p .build/module-cache
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFT_MODULECACHE_PATH="$PWD/.build/module-cache"
swiftc -swift-version 5 Sources/TokenMeterCore.swift Tests/main.swift -o .build/tmeter-tests
.build/tmeter-tests
```

## Project layout

- `Sources/TokenMeterApp.swift`: macOS interface, Dock tile, menu bar, and login item
- `Sources/TokenMeterCore.swift`: local usage readers and parsers
- `Tests/main.swift`: parser checks with local fixtures
- `Tests/LiveCheck.swift`: optional check against local ChatGPT and Claude data
