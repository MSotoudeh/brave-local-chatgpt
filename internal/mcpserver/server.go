package mcpserver

import (
	"context"
	"encoding/json"
	"fmt"
	"sync/atomic"

	"github.com/MSotoudeh/brave-local-chatgpt/internal/bridge"
)

type Caller interface {
	Call(context.Context, bridge.Request) (bridge.Response, error)
}

type Server struct {
	caller Caller
	seq    uint64
}

type rpcRequest struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params,omitempty"`
}

func New(c Caller) *Server { return &Server{caller: c} }

func response(id json.RawMessage, result any) ([]byte, bool) {
	b, _ := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": id, "result": result,
	})
	return b, true
}

func rpcErr(id json.RawMessage, code int, msg string) ([]byte, bool) {
	b, _ := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": id,
		"error": map[string]any{"code": code, "message": msg},
	})
	return b, true
}

func (s *Server) Handle(ctx context.Context, raw []byte) ([]byte, bool) {
	var req rpcRequest
	if err := json.Unmarshal(raw, &req); err != nil {
		return rpcErr(nil, -32700, "parse error")
	}
	if req.Method == "notifications/initialized" || len(req.ID) == 0 {
		return nil, false
	}
	switch req.Method {
	case "initialize":
		return s.initialize(req)
	case "tools/list":
		return response(req.ID, map[string]any{"tools": toolDefinitions()})
	case "tools/call":
		return s.callTool(ctx, req)
	case "ping":
		return response(req.ID, map[string]any{})
	default:
		return rpcErr(req.ID, -32601, "method not found")
	}
}

func (s *Server) initialize(req rpcRequest) ([]byte, bool) {
	version := "2025-06-18"
	var p struct {
		ProtocolVersion string `json:"protocolVersion"`
	}
	if json.Unmarshal(req.Params, &p) == nil && p.ProtocolVersion != "" {
		version = p.ProtocolVersion
	}
	return response(req.ID, map[string]any{
		"protocolVersion": version,
		"capabilities": map[string]any{
			"tools": map[string]any{"listChanged": false},
		},
		"serverInfo": map[string]any{
			"name": "brave-local", "version": "0.2.0",
		},
	})
}

func objSchema(properties map[string]any, required ...string) map[string]any {
	s := map[string]any{
		"type": "object", "properties": properties,
		"additionalProperties": false,
	}
	if len(required) > 0 {
		s["required"] = required
	}
	return s
}

func commonWindowProps() map[string]any {
	return map[string]any{
		"window":   map[string]any{"type": "integer", "minimum": 0},
		"windowId": map[string]any{"type": "integer"},
	}
}

func withCommon(extra map[string]any) map[string]any {
	p := commonWindowProps()
	for k, v := range extra {
		p[k] = v
	}
	return p
}

func tool(name, description string, schema map[string]any) map[string]any {
	return map[string]any{
		"name": name, "description": description, "inputSchema": schema,
	}
}

func toolDefinitions() []map[string]any {
	str := func(desc string) map[string]any {
		return map[string]any{"type": "string", "description": desc}
	}
	integer := func(desc string) map[string]any {
		return map[string]any{"type": "integer", "description": desc, "minimum": 0}
	}
	return []map[string]any{
		tool("list_tabs", "List tabs across every currently open Brave window/profile.",
			objSchema(map[string]any{})),
		tool("activate_tab", "Activate one Brave tab.",
			objSchema(withCommon(map[string]any{"tab": integer("Tab index returned by list_tabs")}), "tab")),
		tool("open_url", "Open a URL in the selected or specified Brave window.",
			objSchema(withCommon(map[string]any{"url": str("Absolute URL")}), "url")),
		tool("snapshot", "Read semantic page elements from the selected tab.",
			objSchema(commonWindowProps())),
		tool("get_text", "Read visible semantic text from the selected tab.",
			objSchema(commonWindowProps())),
		tool("click", "Click a unique semantic element by accessible name and optional role.",
			objSchema(withCommon(map[string]any{
				"name": str("Accessible name"), "role": str("Optional UI Automation role"),
			}), "name")),
		tool("type_text", "Set text in a unique editable field by accessible name.",
			objSchema(withCommon(map[string]any{
				"name": str("Accessible name"), "text": str("Text to enter"),
			}), "name", "text")),
		tool("press_key", "Invoke a supported key action on a semantic target.",
			objSchema(withCommon(map[string]any{
				"key": str("Currently Enter"),
				"name": str("Optional target name"), "role": str("Optional target role"),
			}), "key")),
		tool("scroll", "Scroll the selected page.",
			objSchema(withCommon(map[string]any{
				"direction": map[string]any{"type": "string", "enum": []string{"up", "down"}},
				"pages": integer("Number of page-sized scroll steps"),
			}))),
		tool("wait_for", "Wait until a unique semantic element appears.",
			objSchema(withCommon(map[string]any{
				"name": str("Accessible name"), "role": str("Optional role"),
				"timeoutMs": integer("Timeout in milliseconds, maximum 15000"),
			}), "name")),
		tool("screenshot", "Capture the selected Brave window.",
			objSchema(commonWindowProps())),
	}
}

func toolCommand(name string) (string, bool) {
	m := map[string]string{
		"list_tabs": "tabs.list", "activate_tab": "tabs.activate",
		"open_url": "page.open", "snapshot": "page.snapshot",
		"get_text": "page.text", "click": "element.click",
		"type_text": "element.type", "press_key": "keyboard.press",
		"scroll": "page.scroll", "wait_for": "page.wait",
		"screenshot": "page.screenshot",
	}
	v, ok := m[name]
	return v, ok
}

func (s *Server) callTool(ctx context.Context, req rpcRequest) ([]byte, bool) {
	var p struct {
		Name      string         `json:"name"`
		Arguments map[string]any `json:"arguments"`
	}
	if err := json.Unmarshal(req.Params, &p); err != nil {
		return rpcErr(req.ID, -32602, "invalid tool parameters")
	}
	command, ok := toolCommand(p.Name)
	if !ok {
		return rpcErr(req.ID, -32602, "unknown tool")
	}
	if p.Arguments == nil {
		p.Arguments = map[string]any{}
	}
	if p.Name == "type_text" {
		if v, ok := p.Arguments["text"]; ok {
			p.Arguments["value"] = v
			delete(p.Arguments, "text")
		}
	}
	paramBytes, _ := json.Marshal(p.Arguments)
	internalID := fmt.Sprintf("mcp-%d", atomic.AddUint64(&s.seq, 1))
	resp, err := s.caller.Call(ctx, bridge.Request{
		ID: internalID, Command: command, Params: paramBytes,
	})
	if err != nil {
		return response(req.ID, toolError("bridge_error", err.Error()))
	}
	if !resp.OK {
		code, msg := "bridge_error", "bridge operation failed"
		if resp.Error != nil {
			code, msg = resp.Error.Code, resp.Error.Message
		}
		return response(req.ID, toolError(code, msg))
	}
	var decoded any
	if len(resp.Result) > 0 {
		if err := json.Unmarshal(resp.Result, &decoded); err != nil {
			decoded = string(resp.Result)
		}
	}
	textBytes, _ := json.Marshal(decoded)
	return response(req.ID, map[string]any{
		"content": []map[string]any{{"type": "text", "text": string(textBytes)}},
		"structuredContent": map[string]any{"result": decoded},
		"isError": false,
	})
}

func toolError(code, message string) map[string]any {
	text := fmt.Sprintf("%s: %s", code, message)
	return map[string]any{
		"content": []map[string]any{{"type": "text", "text": text}},
		"structuredContent": map[string]any{"error": map[string]any{"code": code, "message": message}},
		"isError": true,
	}
}
