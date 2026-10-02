# Brave Local for ChatGPT

Brave Local is a Windows desktop plugin that lets ChatGPT work with the Brave browser that is already open on the same PC.

It does **not** require:

- a device name
- a Windows username
- a predefined Brave profile
- a second automation browser
- an OpenAI browser extension
- a remote debugging port
- Remote Desktop Commander at runtime

The plugin discovers all currently open Brave windows and treats every open profile as a candidate.

## Requirements

- Windows 10/11
- Brave Browser
- ChatGPT Desktop with local plugin/MCP support
- PowerShell 5.1+ (included with Windows)

## Install from ZIP

1. Download `brave-local-<version>-windows.zip`.
2. In ChatGPT Desktop open **Plugins**.
3. Select **+ → Upload plugin**.
4. Choose the ZIP.
5. Open Brave normally.
6. Mention `@Brave` in a chat.

## Install from a Git marketplace

The repository contains:

`.agents/plugins/marketplace.json`

A user can add the repository as a plugin marketplace with the Codex/ChatGPT CLI:

```powershell
codex plugin marketplace add <owner>/<repo>
```

or:

```powershell
codex plugin marketplace add https://github.com/<owner>/<repo>.git
```

Then install **Brave** from that marketplace in ChatGPT Desktop.

## How routing works

`list_tabs` enumerates tabs across all currently open Brave top-level windows. Each result includes a runtime `windowId`.

If an action does not specify a window:

1. the only open Brave window is used; otherwise
2. the currently focused Brave window is used; otherwise
3. the operation fails with `ambiguous_window`.

The model should call `list_tabs` and use the returned `windowId` when a request spans multiple windows/profiles.

## Exposed tools

- `list_tabs`
- `activate_tab`
- `open_url`
- `snapshot`
- `get_text`
- `click`
- `type_text`
- `press_key`
- `scroll`
- `wait_for`
- `screenshot`

## Security model

The plugin controls the browser UI that the signed-in Windows user already has open. It does not provide tools to export cookies, browser storage, passwords, or reusable authentication material.

There is no TCP listener and no Chrome/Brave remote-debugging port. The bundled MCP server uses stdio between ChatGPT Desktop and a local process.

## Build

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build-distributable.ps1
```

The Windows ZIP is written to `dist/`.

## Current scope

Version 0.2.x is Windows-only. macOS and Linux require separate accessibility backends.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Installation and distribution](docs/INSTALLATION.md)
- [Security model](docs/SECURITY.md)
- [Testing and validation](docs/TESTING.md)
- [v0.2.1 release notes](docs/RELEASE-0.2.1.md)

## Current release

The current Windows release is **v0.2.1**:

https://github.com/MSotoudeh/brave-local-chatgpt/releases/tag/v0.2.1
