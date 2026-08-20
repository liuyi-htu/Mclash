package main

import (
	"os"
	"testing"
)

func TestSettingsAndRuntimeStateAreSeparated(t *testing.T) {
	paths, err := resolvePaths(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	if err := paths.ensureDataDirs(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		paths.Settings,
		[]byte(`{"coreType":"sing-box","debugLoggingEnabled":true}`),
		0o644,
	); err != nil {
		t.Fatal(err)
	}
	if err := writeRuntimeState(paths, 321, "startup failed"); err != nil {
		t.Fatal(err)
	}

	settings := readSettings(paths)
	if settings["coreType"] != "sing-box" || settings["debugLoggingEnabled"] != true {
		t.Fatalf("settings = %#v", settings)
	}
	runtime := readRuntimeState(paths)
	if runtime.MihomoPID != 321 || runtime.Message != "startup failed" {
		t.Fatalf("runtime = %#v", runtime)
	}
	if err := clearRuntimeMessage(paths); err != nil {
		t.Fatal(err)
	}
	runtime = readRuntimeState(paths)
	if runtime.MihomoPID != 321 || runtime.Message != "" {
		t.Fatalf("cleared runtime = %#v", runtime)
	}
	settings = readSettings(paths)
	if _, exists := settings["mihomoPid"]; exists {
		t.Fatalf("runtime PID leaked into settings: %#v", settings)
	}
}

func TestLegacyStateRemainsReadableDuringMigration(t *testing.T) {
	paths, err := resolvePaths(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	if err := paths.ensureDataDirs(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(
		paths.LegacyState,
		[]byte(`{"coreType":"sing-box","debugLoggingEnabled":true,"mihomoPid":42,"message":"legacy"}`),
		0o644,
	); err != nil {
		t.Fatal(err)
	}

	settings := readSettings(paths)
	if settings["coreType"] != "sing-box" {
		t.Fatalf("legacy settings = %#v", settings)
	}
	if _, exists := settings["message"]; exists {
		t.Fatalf("runtime message leaked into migrated settings: %#v", settings)
	}
	runtime := readRuntimeState(paths)
	if runtime.MihomoPID != 42 || runtime.Message != "legacy" {
		t.Fatalf("legacy runtime = %#v", runtime)
	}
}
