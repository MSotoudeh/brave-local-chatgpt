package mcpserver

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/MSotoudeh/brave-local-chatgpt/internal/bridge"
)

type fakeCaller struct {
	last bridge.Request
	resp bridge.Response
}

func (f *fakeCaller) Call(_ context.Context, req bridge.Request) (bridge.Response, error) {
	f.last = req
	return f.resp, nil
}

func decodeObject(t *testing.T, raw []byte) map[string]any {
	t.Helper()
	var v map[string]any
	if err := json.Unmarshal(raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func TestInitializeAdvertisesTools(t *testing.T) {
	s := New(&fakeCaller{})
	raw, respond := s.Handle(context.Background(), []byte(
		`{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}`,
	))
	if !respond {
		t.Fatal("expected response")
	}
	got := decodeObject(t, raw)
	result := got["result"].(map[string]any)
	if result["protocolVersion"] != "2025-06-18" {
		t.Fatalf("protocolVersion=%v", result["protocolVersion"])
	}
	caps := result["capabilities"].(map[string]any)
	if _, ok := caps["tools"]; !ok {
		t.Fatal("tools capability missing")
	}
}

func TestToolsListContainsBrowserSurface(t *testing.T) {
	s := New(&fakeCaller{})
	raw, _ := s.Handle(context.Background(), []byte(
		`{"jsonrpc":"2.0","id":"x","method":"tools/list","params":{}}`,
	))
	got := decodeObject(t, raw)
	result := got["result"].(map[string]any)
	tools := result["tools"].([]any)
	names := map[string]bool{}
	for _, item := range tools {
		m := item.(map[string]any)
		names[m["name"].(string)] = true
	}
	for _, want := range []string{
		"list_tabs", "activate_tab", "open_url", "snapshot", "get_text",
		"click", "type_text", "press_key", "scroll", "wait_for", "screenshot",
	} {
		if !names[want] {
			t.Fatalf("missing tool %q", want)
		}
	}
}

func TestToolsCallMapsListTabsToBridge(t *testing.T) {
	f := &fakeCaller{resp: bridge.Response{
		ID: "internal", OK: true, Result: json.RawMessage(`[{"window":0,"tab":1,"title":"GitHub"}]`),
	}}
	s := New(f)
	raw, _ := s.Handle(context.Background(), []byte(
		`{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"list_tabs","arguments":{}}}`,
	))
	if f.last.Command != "tabs.list" {
		t.Fatalf("command=%q", f.last.Command)
	}
	got := decodeObject(t, raw)
	result := got["result"].(map[string]any)
	if result["isError"] == true {
		t.Fatalf("unexpected tool error: %s", raw)
	}
}
