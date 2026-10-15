"""Regression tests for Brave local MCP stdio behavior.

Isolated PowerShell process with a synthetic UIA worker. Never opens Brave,
touches real profile data or attaches to a running Codex MCP session.
"""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SERVER = ROOT / "scripts" / "brave-local-mcp.ps1"
MIRROR = ROOT / "plugins" / "brave-local" / "scripts" / "brave-local-mcp.ps1"
PWSH5 = Path(r"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")

FAKE_WORKER = r"""
param([string]$RequestPath,[string]$ResponsePath)
$ErrorActionPreference='Stop'
$inputJson=Get-Content $RequestPath -Raw|ConvertFrom-Json
$result=@{ok=$true;result=@{tabs=@(@{index=0;title='Synthetic tab';url='about:blank'});operation=$inputJson.command}}
$result|ConvertTo-Json -Depth 10 -Compress | Set-Content -LiteralPath $ResponsePath -Encoding UTF8
"""

def frame(method=None, request_id=None, params=None, **extra):
    v = {"jsonrpc": "2.0"}
    if method is not None:
        v["method"] = method
    if request_id is not None:
        v["id"] = request_id
    if params is not None:
        v["params"] = params
    v.update(extra)
    return json.dumps(v, ensure_ascii=False)


class StdioGuardTest(unittest.TestCase):
    def test_source_and_packaged_server_equal(self):
        self.assertEqual(SERVER.read_bytes(), MIRROR.read_bytes())

    def test_responses_do_not_generate_new_errors(self):
        self.assertTrue(PWSH5.exists())
        with tempfile.TemporaryDirectory(prefix="BraveMcpSynthetic_") as directory:
            base = Path(directory)
            plugin = base / "plugin"
            scripts = plugin / "scripts"
            scripts.mkdir(parents=True)
            (scripts / "uia-command.ps1").write_text(FAKE_WORKER, encoding="utf-8")
            env = os.environ.copy()
            env["PLUGIN_ROOT"] = str(plugin)
            env["PLUGIN_DATA"] = str(base / "data")
            env["LOCALAPPDATA"] = str(base / "localapp")
            env["BRAVE_MCP_TRACE"] = "1"
            messages = [
                frame("initialize", 1, {"protocolVersion": "2025-06-18"}),
                frame("tools/list", 2),
                frame("tools/call", 3, {"name": "list_tabs", "arguments": {}}),
                frame(request_id=3, result={"from": "client", "ok": True}),
                frame(request_id=56, error={"code": -32601, "message": "Already a response"}),
                frame("notifications/initialized"),
            ]
            messages.extend(frame(request_id=i, result={}) for i in range(100, 1600))
            messages.append(frame("ping", 4))
            proc = subprocess.run(
                [str(PWSH5), "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(SERVER)],
                input="\n".join(messages) + "\n", text=True, encoding="utf-8",
                capture_output=True, timeout=35, env=env,
            )
            self.assertEqual(proc.returncode, 0, msg=proc.stderr[-1200:])
            replies = [json.loads(line) for line in proc.stdout.splitlines() if line.strip()]
            self.assertEqual([o.get("id") for o in replies], [1, 2, 3, 4], msg=proc.stdout[-1200:])
            self.assertEqual(replies[0]["result"]["serverInfo"]["name"], "brave-local")
            self.assertIn("tools", replies[1]["result"])
            result = replies[2]["result"]
            self.assertFalse(result["isError"], msg=result)
            self.assertEqual(result["structuredContent"]["result"]["operation"], "tabs.list")
            self.assertEqual(result["structuredContent"]["result"]["tabs"][0]["title"], "Synthetic tab")
            self.assertEqual(replies[3]["result"], {})
            trace = base / "localapp" / "BraveLocalRecovery" / "20261015" / "mcp-rpc-trace.log"
            self.assertTrue(trace.exists(), "diagnostic trace missing")
            self.assertLess(trace.stat().st_size, 64000, "invalid messages flooded trace")
            self.assertIn("ignored-nonrequest", trace.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
