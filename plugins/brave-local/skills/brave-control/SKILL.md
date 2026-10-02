---
name: brave-control
description: Use when the user invokes @Brave or asks to inspect, navigate, read, or interact with any currently open Brave window or profile on the same Windows PC.
---

# Brave Control

Use the bundled `brave-local` MCP tools. Do not require the user to provide a computer name, Windows username, Brave profile name, or profile directory.

Treat every currently open Brave window as a candidate, regardless of profile. If the target is not already unambiguous, call `list_tabs` first.

## Routing

- If the request identifies a unique tab by title/content, use that tab.
- If only one Brave window is open, it is the default.
- If multiple Brave windows are open, prefer the currently focused Brave window when the runtime can determine it.
- If multiple candidates remain ambiguous, ask the user rather than guessing.
- Use `windowId` returned by `list_tabs` when continuing a multi-step operation.

## Interaction discipline

Before clicking or typing into an unfamiliar page, call `snapshot` and target a unique accessible name/role. If a tool returns `ambiguous_target`, refine the target; never choose one arbitrarily.

Use the tools directly:

- `list_tabs`, `activate_tab`
- `open_url`
- `snapshot`, `get_text`
- `click`, `type_text`, `press_key`
- `scroll`, `wait_for`, `screenshot`

Do not export cookies, passwords, browser storage, reusable authentication material, or raw credentials. The browser should use its own already-authorized session.

Do not substitute a separate automation browser, another Brave profile, web search, or the OpenAI browser extension unless the user explicitly asks.

If Brave is not running or the local MCP process cannot access the interactive desktop, report that condition clearly.
