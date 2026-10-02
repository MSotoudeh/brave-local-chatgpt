# Architecture

Brave Local is a Windows-local ChatGPT plugin for operating the Brave browser session that is already open on the same PC.

## Runtime flow

```text
ChatGPT Desktop
  -> plugin skill (@Brave)
  -> local MCP over stdio
  -> scripts/brave-local-mcp.ps1
  -> scripts/uia-command.ps1
  -> Windows UI Automation
  -> any currently open Brave window/profile
```

The runtime does not depend on a device name, Windows username, Brave profile name, Remote Desktop Commander, a browser extension, or a remote-debugging port.

## Window and profile routing

`list_tabs` enumerates every currently open top-level Brave window and returns a runtime `windowId`. Profiles are not configured in advance. If one window is open it is the default; with multiple windows the focused Brave window is preferred. If routing is still ambiguous, the operation fails closed with `ambiguous_window`.

## Tool surface

`list_tabs`, `activate_tab`, `open_url`, `snapshot`, `get_text`, `click`, `type_text`, `press_key`, `scroll`, `wait_for`, and `screenshot`.

Read/write actions use semantic UI Automation names and roles where possible. `snapshot` should be used before unfamiliar click/type operations.
