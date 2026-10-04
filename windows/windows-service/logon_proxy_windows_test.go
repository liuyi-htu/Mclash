package main

import "testing"

func TestLogonProxyUsesValidMixedOrHTTPPort(t *testing.T) {
	for _, item := range []struct {
		config string
		want   int
	}{
		{"mixed-port: 7890\nport: 8080\n", 7890},
		{"mixed-port: 0\nport: '8080' # fallback\n", 8080},
		{"mixed-port: 70000\n", 0},
	} {
		got, err := proxyPortFromConfig(item.config)
		if item.want == 0 {
			if err == nil {
				t.Fatal("expected invalid port error")
			}
			continue
		}
		if err != nil || got != item.want {
			t.Fatalf("got=%d err=%v want=%d", got, err, item.want)
		}
	}
	if isMutation("sync-user-proxy") {
		t.Fatal("login hook must run as current user without elevation")
	}
}
