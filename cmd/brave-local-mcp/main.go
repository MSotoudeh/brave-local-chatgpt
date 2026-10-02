package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/MSotoudeh/brave-local-chatgpt/internal/bridge"
	"github.com/MSotoudeh/brave-local-chatgpt/internal/mcpserver"
)

func pluginRootFor(exePath, override string) string {
	if override != "" {
		return filepath.Clean(override)
	}
	dir := filepath.Dir(exePath)
	if strings.EqualFold(filepath.Base(dir), "windows") {
		return filepath.Dir(filepath.Dir(dir))
	}
	return filepath.Dir(exePath)
}

func dataRootFor(pluginData, fallback string) string {
	if pluginData != "" {
		return filepath.Clean(pluginData)
	}
	return filepath.Join(fallback, "brave-local")
}

type uiaCaller struct {
	pluginRoot string
	dataRoot   string
}

func (u *uiaCaller) Call(ctx context.Context, req bridge.Request) (bridge.Response, error) {
	tmpDir := filepath.Join(u.dataRoot, "tmp")
	if err := os.MkdirAll(tmpDir, 0o700); err != nil {
		return bridge.Response{}, err
	}
	reqFile, err := os.CreateTemp(tmpDir, "req-*.json")
	if err != nil {
		return bridge.Response{}, err
	}
	reqPath := reqFile.Name()
	defer os.Remove(reqPath)
	resPath := reqPath + ".res.json"
	defer os.Remove(resPath)

	if err := json.NewEncoder(reqFile).Encode(req); err != nil {
		reqFile.Close()
		return bridge.Response{}, err
	}
	if err := reqFile.Close(); err != nil {
		return bridge.Response{}, err
	}

	script := filepath.Join(u.pluginRoot, "scripts", "uia-command.ps1")
	cmd := exec.CommandContext(ctx, "powershell.exe",
		"-NoProfile", "-ExecutionPolicy", "Bypass",
		"-File", script, "-RequestPath", reqPath, "-ResponsePath", resPath,
	)
	cmd.Env = append(os.Environ(),
		"BRAVE_LOCAL_DATA="+u.dataRoot,
		"BRAVE_LOCAL_PLUGIN_ROOT="+u.pluginRoot,
	)
	if out, err := cmd.CombinedOutput(); err != nil {
		return bridge.Response{}, fmt.Errorf("uia worker: %w: %s", err, strings.TrimSpace(string(out)))
	}
	raw, err := os.ReadFile(resPath)
	if err != nil {
		return bridge.Response{}, err
	}
	resp, err := decodeBridgeResponse(raw)
	if err != nil {
		return bridge.Response{}, fmt.Errorf("parse UIA response: %w", err)
	}
	return resp, nil
}

func decodeBridgeResponse(raw []byte) (bridge.Response, error) {
	raw = bytes.TrimPrefix(raw, []byte{0xef, 0xbb, 0xbf})
	var resp bridge.Response
	err := json.Unmarshal(raw, &resp)
	return resp, err
}

func roots() (string, string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", "", err
	}
	pluginRoot := pluginRootFor(exe, os.Getenv("PLUGIN_ROOT"))
	cache, err := os.UserCacheDir()
	if err != nil {
		cache = filepath.Dir(exe)
	}
	return pluginRoot, dataRootFor(os.Getenv("PLUGIN_DATA"), cache), nil
}

func run() error {
	pluginRoot, dataRoot, err := roots()
	if err != nil {
		return err
	}
	caller := &uiaCaller{pluginRoot: pluginRoot, dataRoot: dataRoot}
	server := mcpserver.New(caller)

	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 64*1024), 2*1024*1024)
	writer := bufio.NewWriter(os.Stdout)
	defer writer.Flush()

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		resp, respond := server.Handle(ctx, []byte(line))
		cancel()
		if !respond {
			continue
		}
		if _, err := writer.Write(resp); err != nil {
			return err
		}
		if err := writer.WriteByte('\n'); err != nil {
			return err
		}
		if err := writer.Flush(); err != nil {
			return err
		}
	}
	return scanner.Err()
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
