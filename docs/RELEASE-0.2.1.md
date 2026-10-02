# Release v0.2.1

v0.2.1 is the current Windows release.

## Main change

The local MCP runtime is PowerShell-based and ships as scripts inside the plugin instead of requiring the compiled Go MCP binary used by the initial v0.2.0 package. This reduces the release archive to roughly 9.6 KB while keeping the same profile-agnostic Windows UI Automation backend.

## Package contents

- plugin manifests
- local stdio MCP configuration
- `scripts/brave-local-mcp.ps1`
- UI Automation worker and screenshot helper
- `skills/brave-control/SKILL.md`

## Release evidence

GitHub release asset: `brave-local-0.2.1-windows.zip`

Published asset SHA-256: `7653510c65a82e3e9935012a58419b2a198c26950135c5823b2ba1d426a62b85`

The current GitHub Actions handoff artifact was also imported into ChatGPT Plugin Creator and accepted as plugin version `0.2.1`.

## Scope

Windows only. The architecture intentionally avoids per-profile extension installation and treats every open Brave profile/window as a runtime candidate.
