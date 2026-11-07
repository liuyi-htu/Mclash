package main

import "testing"

func TestControllerSnapshotOverridesPendingSettings(t *testing.T) {
	state := map[string]any{"coreConnection": map[string]any{"controller": "127.0.0.1:9999", "secret": "pending"}, "runtimeController": map[string]any{"controller": "0.0.0.0:9191", "secret": "active"}}
	endpoint, secret, err := controllerRequestFromSettings(state, "fallback")
	if err != nil || endpoint != "http://127.0.0.1:9191/version" || secret != "active" {
		t.Fatalf("unexpected controller snapshot: %s %v", endpoint, err)
	}
}
func TestControllerIpv6AndLegacyFallback(t *testing.T) {
	endpoint, _, err := controllerRequestFromSettings(map[string]any{"runtimeController": map[string]any{"controller": "[::]:9191"}}, "fallback")
	if err != nil || endpoint != "http://[::1]:9191/version" {
		t.Fatalf("unexpected IPv6 endpoint: %s %v", endpoint, err)
	}
	endpoint, secret, err := controllerRequestFromSettings(nil, "legacy")
	if err != nil || endpoint != "legacy" || secret != "" {
		t.Fatal("legacy controller changed")
	}
}
