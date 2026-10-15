# Codex Brave MCP response-path recovery — 2026-10-15

Source of investigation: existing Codex Desktop thread
`01a13198-016b-7761-b002-323827817ae8`, recorded on Ops at
`C:\Users\mmsot\.codex\sessions\2026\10\12\rollout-2026-10-12T21-30-07-01a13198-016b-7761-b002-323827817ae8.jsonl`.

## Goal and last observed state

The Codex thread's continuing user goal was to resolve two failures:
(1) Iran Project IR Preview Agent on Mehdi-PC, and (2) locally installed
Brave MCP in Codex Desktop.

Codex reported fresh, authenticated read-only command receipts from
Mehdi-PC over the Preview Poll transport on 2026-10-15: cmd returned
`Mehdi-PC`, and PowerShell returned `MEHDI-PC` and
`NT AUTHORITY\SYSTEM`. This is the thread's last proof for the first
goal, not a fresh independent end-to-end test by this branch.

For Brave, Codex's last progress report at 11:32 UTC showed:
`list_tabs` reached the MCP server and a UIA worker completed in
approximately 4 seconds, but the upstream Codex invocation did not
receive the response. The MCP trace also recorded a large volume of
inbound frames without a JSON-RPC `method`.

## Defect and isolated change

The local PowerShell JSON-RPC server used to send `-32601 Method not
found` to every parseable input object without a `method`. JSON-RPC
responses have a `result` or `error` but no `method`; replying to
such non-request objects can cause a repeated error exchange in a
miswired/feedback-loop transport. This matches the evidence but the
underlying host-side forwarding behavior remains unverified.

Both mirrored MCP scripts now ignore non-request objects and one-way
notifications. Diagnostic RPC metadata tracing is opt-in with
`BRAVE_MCP_TRACE=1`, without capturing page contents or typed input.
The previous 20-second UIA subprocess deadline and cleanup changes
from the interrupted Codex work were carried into this isolated branch.

## Validation

- Both PowerShell scripts parse with zero syntax errors.
- `tests/test_stdio_protocol.py`: Python unittest against a
  **synthetic** local UIA worker, with real PowerShell 5.1 MCP server
  stdio. Initialization, tool listing, a simulated `list_tabs` tool
  call, and ping receive the four expected responses in order.
- 1,500 inbound JSON-RPC objects with no method plus a notification
  produce no extra responses; trace size is bounded.
- The same regression test against the unchanged active-source
  script failed as expected, showing that the test distinguishes the
  old and new behavior.
- `git diff --check` clean.

## Safety, rollout, and remaining checks

This was implemented in isolated Worktree:
`C:\GitHub\brave-local-worktrees\brave-mcp-stdio-guard-20261015`.

The original Git worktree, the Codex plugin cache, installed MCP server
processes, browser windows, and the Codex application have **not** been
modified/restarted by these steps. Existing uncommitted changes in
`C:\GitHub\brave-local-chatgpt` belong to prior Codex work and remain
untouched.

Next: coordinate with active Codex sessions, move reviewed patch from
this branch to the plugin's approved installation path, restart only
the corresponding MCP session under the Windows interactive owner,
then call Codex's **real** Brave `list_tabs` tool. Confirm successful
result delivery (not merely worker completion), and remove temporary
diagnostics after verification. Do not claim production resolved until
that live acceptance test is complete.

The Iran Preview device uses an independent Hub and should not be
mistaken for the main Project IR Hub's device-status endpoint. Avoid
rebooting the remote laptop or re-enrolling its agent as part of the
Brave repair.
