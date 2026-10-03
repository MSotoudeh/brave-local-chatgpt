# Security model

Brave Local deliberately uses the browser UI that the signed-in Windows user already controls.

## Explicit non-features

- no cookie export
- no browser-storage export
- no password or reusable credential export
- no TCP/UDP listener
- no Chrome/Brave remote-debugging port
- no dependency on the OpenAI browser extension
- no automatic switch to a different browser/profile

## Local trust boundary

ChatGPT Desktop starts the bundled MCP locally over stdio. The MCP invokes Windows UI Automation against Brave windows in the interactive user desktop.

## Action safety

Semantic targets are preferred over fixed coordinates. Ambiguous element matches return `ambiguous_target`; ambiguous window selection returns `ambiguous_window`. The skill instructs the model to take a snapshot and refine the target rather than guess.

The browser itself owns authentication state, so requests run with whatever access the currently open browser session already has.

## Limitations

A local plugin with browser-control capabilities is powerful. Users should install only archives/repositories they trust and review ChatGPT plugin permission prompts. Version 0.2.x is Windows-only.
