package bridge

import (
	"encoding/json"
	"errors"
	"fmt"
)

const MaxRequestSize = 1024 * 1024

type Request struct {
	ID      string          `json:"id"`
	Command string          `json:"command"`
	Params  json.RawMessage `json:"params,omitempty"`
}

type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}
type Response struct {
	ID     string          `json:"id"`
	OK     bool            `json:"ok"`
	Result json.RawMessage `json:"result,omitempty"`
	Error  *ErrorBody      `json:"error,omitempty"`
}

var AllowedCommands = map[string]struct{}{
	"tabs.list": {}, "tabs.activate": {}, "page.open": {},
	"page.snapshot": {}, "page.text": {}, "element.click": {},
	"element.type": {}, "keyboard.press": {}, "page.scroll": {},
	"page.wait": {}, "page.screenshot": {},
}

func ValidateRequest(r Request) error {
	if r.ID == "" {
		return errors.New("missing id")
	}
	if r.Command == "" {
		return errors.New("missing command")
	}
	if _, ok := AllowedCommands[r.Command]; !ok {
		return fmt.Errorf("unknown command: %s", r.Command)
	}
	if len(r.Params) > MaxRequestSize {
		return errors.New("params too large")
	}
	if len(r.Params) > 0 && !json.Valid(r.Params) {
		return errors.New("invalid params json")
	}
	return nil
}
