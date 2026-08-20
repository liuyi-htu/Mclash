package main

import (
	"encoding/json"
	"testing"
)

func TestDecodeSystemProxyBackupSupportsCurrentAndLegacyFormats(t *testing.T) {
	original := map[string]any{
		"ProxyEnable":   map[string]string{"type": "REG_DWORD", "data": "0x0"},
		"ProxyServer":   map[string]string{"type": "REG_SZ", "data": "old:8080"},
		"ProxyOverride": nil,
	}
	owned := map[string]any{
		"ProxyEnable":   map[string]string{"type": "REG_DWORD", "data": "1"},
		"ProxyServer":   map[string]string{"type": "REG_SZ", "data": "127.0.0.1:7890"},
		"ProxyOverride": map[string]string{"type": "REG_SZ", "data": "<local>"},
	}
	for name, payload := range map[string]any{
		"current": map[string]any{"version": 2, "original": original, "owned": owned},
		"legacy":  original,
	} {
		t.Run(name, func(t *testing.T) {
			data, err := json.Marshal(payload)
			if err != nil {
				t.Fatal(err)
			}
			backup, err := decodeSystemProxyBackup(data)
			if err != nil {
				t.Fatal(err)
			}
			if backup.Original["ProxyServer"].Data != "old:8080" {
				t.Fatalf("original proxy server = %q", backup.Original["ProxyServer"].Data)
			}
			if name == "current" && backup.Owned["ProxyServer"].Data != "127.0.0.1:7890" {
				t.Fatalf("owned proxy server = %q", backup.Owned["ProxyServer"].Data)
			}
			if name == "legacy" && backup.Owned != nil {
				t.Fatalf("legacy owned values = %#v, want nil", backup.Owned)
			}
		})
	}
}
