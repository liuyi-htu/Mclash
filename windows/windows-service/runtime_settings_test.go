package main

import "testing"

func TestRuntimeNetworkSettingsPreservesRunningPreferences(t *testing.T) {
	pending := map[string]any{
		"networkMode": "tun", "bypassLanEnabled": false,
		"runningNetworkMode": "proxy", "runningBypassLanEnabled": true,
	}
	current := runtimeNetworkSettings(pending)
	if current["networkMode"] != "proxy" || current["bypassLanEnabled"] != true {
		t.Fatalf("pending settings applied to running core: %v", current)
	}
	if pending["networkMode"] != "tun" || pending["bypassLanEnabled"] != false {
		t.Fatal("saved settings were modified")
	}
}

func TestRuntimeNetworkSettingsSupportsLegacyAndFalse(t *testing.T) {
	legacy := runtimeNetworkSettings(map[string]any{"networkMode": "tun", "bypassLanEnabled": true})
	if legacy["networkMode"] != "tun" || legacy["bypassLanEnabled"] != true {
		t.Fatalf("legacy settings lost: %v", legacy)
	}
	current := runtimeNetworkSettings(map[string]any{"bypassLanEnabled": true, "runningBypassLanEnabled": false})
	if current["bypassLanEnabled"] != false {
		t.Fatal("explicit runtime false was lost")
	}
}
