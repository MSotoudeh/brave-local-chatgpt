# Installation and distribution

## Requirements

- Windows 10 or 11
- Brave Browser
- ChatGPT Desktop with local plugin/MCP support
- Windows PowerShell 5.1 or newer

## ZIP installation

1. Download the current `brave-local-<version>-windows.zip` release.
2. Open ChatGPT Desktop -> Plugins.
3. Choose **+ -> Upload plugin**.
4. Select the ZIP.
5. Open Brave normally and invoke `@Brave`.

No device name, profile directory, extension install, remote-debugging flag, or separate browser instance is required.

## Git marketplace installation

This repository ships `.agents/plugins/marketplace.json`. Add the repository as a marketplace with the ChatGPT/Codex plugin CLI, then install **Brave** from that marketplace.

## Updating

Install a newer ZIP or update the plugin from the marketplace. The plugin data directory is separate from the package, so package replacement does not require a Brave profile migration.

## Usage examples

- `@Brave list my open Brave tabs`
- `@Brave use the GitHub tab that is already open`
- `@Brave inspect this page, then click the unique Submit button`

If several windows match, the plugin must identify the target using `list_tabs`/`windowId` rather than guessing.

## Licensing note

This repository currently does not declare an open-source license. Public availability on GitHub is not itself a license grant for modification or redistribution. Choose and add a license before inviting third-party forks or redistribution beyond the release/use workflow described here.
