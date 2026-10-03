# Testing and validation

## Local verification

The release is checked with:

```powershell
powershell -File .\scripts\test-mcp-protocol.ps1
powershell -File .\scripts\build-distributable.ps1
powershell -File .\scripts\test-distributable.ps1
git diff --check
```

Latest v0.2.1 verification on the development host returned:

```text
MCP_PROTOCOL_PASS
PACKAGE_VERIFY_PASS
V021_VERIFY_PASS
```

## CI

GitHub Actions runs the protocol/package verification and publishes a handoff artifact. Run `37091241120` on commit `6feb3a155d3af119be2b563dbfac8ed4e9521618` completed successfully and produced the `brave-local-plugin` artifact.

## ChatGPT backend validation

The CI artifact was imported through ChatGPT Plugin Creator and then updated successfully to version `0.2.1` as a private USER-scoped plugin. Plugin Creator canonicalized both the plugin manifest and MCP manifest and retained the PowerShell runtime/scripts.

## Browser-engine validation

The UI Automation engine has been exercised against real Brave windows, including simultaneous windows from different Brave profiles, semantic snapshots, navigation, click, type, key press, scroll, and screenshot operations.

A ChatGPT Desktop refresh/restart may be required before a newly created personal plugin appears in an existing `@` mention picker.
