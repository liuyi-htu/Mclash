package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestAppendUpdateLogRespectsDebugLoggingSwitch(t *testing.T) {
	paths, err := resolvePaths(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	logPath := filepath.Join(paths.Logs, "update.log")

	appendUpdateLog(paths, "disabled")
	if _, err := os.Stat(logPath); !os.IsNotExist(err) {
		t.Fatalf("update log exists while debug logging is disabled: %v", err)
	}

	setDebugLoggingForTest(t, paths, true)
	appendUpdateLog(paths, "enabled message")
	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "enabled message") {
		t.Fatalf("update log = %q, want enabled message", data)
	}
}

func TestDebugLogWriterCreatesAndWritesOnlyWhileEnabled(t *testing.T) {
	paths, err := resolvePaths(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	writer := &debugLogWriter{paths: paths, path: paths.MihomoLog}
	t.Cleanup(func() { _ = writer.Close() })

	if _, err := writer.Write([]byte("disabled")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(paths.MihomoLog); !os.IsNotExist(err) {
		t.Fatalf("core log exists while debug logging is disabled: %v", err)
	}

	setDebugLoggingForTest(t, paths, true)
	if _, err := writer.Write([]byte("enabled")); err != nil {
		t.Fatal(err)
	}
	setDebugLoggingForTest(t, paths, false)
	if _, err := writer.Write([]byte("ignored")); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(paths.MihomoLog)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "enabled" {
		t.Fatalf("core log = %q, want only enabled output", data)
	}
}

func setDebugLoggingForTest(t *testing.T, paths appPaths, enabled bool) {
	t.Helper()
	if err := paths.ensureDataDirs(); err != nil {
		t.Fatal(err)
	}
	value := "false"
	if enabled {
		value = "true"
	}
	if err := os.WriteFile(paths.Settings, []byte(`{"debugLoggingEnabled":`+value+`}`), 0o644); err != nil {
		t.Fatal(err)
	}
}
