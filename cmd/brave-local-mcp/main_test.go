package main

import (
	"path/filepath"
	"testing"
)

func TestPluginRootPrefersEnvironment(t *testing.T) {
	if got := pluginRootFor("C:\\x\\bin\\windows\\server.exe", "D:\\plugin"); got != "D:\\plugin" {
		t.Fatalf("got %q", got)
	}
}

func TestPluginRootDerivesFromBundledWindowsBinary(t *testing.T) {
	exe := filepath.Join("C:\\plugin", "bin", "windows", "brave-local-mcp.exe")
	want := filepath.Clean("C:\\plugin")
	if got := pluginRootFor(exe, ""); got != want {
		t.Fatalf("got %q want %q", got, want)
	}
}

func TestDataRootPrefersPluginData(t *testing.T) {
	if got := dataRootFor("D:\\data", "C:\\cache"); got != "D:\\data" {
		t.Fatalf("got %q", got)
	}
}

func TestDecodeBridgeResponseAcceptsUTF8BOM(t *testing.T) {
	raw := append([]byte{0xef, 0xbb, 0xbf}, []byte(`{"id":"x","ok":true,"result":[]}`)...)
	resp, err := decodeBridgeResponse(raw)
	if err != nil {
		t.Fatal(err)
	}
	if !resp.OK || resp.ID != "x" {
		t.Fatalf("unexpected response: %+v", resp)
	}
}
