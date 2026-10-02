package portable

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, _ := runtime.Caller(0)
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", ".."))
}

func TestBundledUIScriptsContainNoMachineSpecificIdentity(t *testing.T) {
	root := repoRoot(t)
	files := []string{
		filepath.Join(root, "scripts", "uia-command.ps1"),
		filepath.Join(root, "scripts", "uia-printwindow.ps1"),
	}
	for _, path := range files {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		text := strings.ToLower(string(raw))
		for _, forbidden := range []string{"mmsot", "ops\\", "c:\\users\\", "bravechatgptbridge"} {
			if strings.Contains(text, forbidden) {
				t.Fatalf("%s contains machine-specific token %q", path, forbidden)
			}
		}
	}
}
