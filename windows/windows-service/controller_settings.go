package main

import (
	"fmt"
	"net"
	"net/url"
)

// The snapshot is written together with runtime generation, before SCM startup.
func controllerRequestFromSettings(settings map[string]any, fallback string) (string, string, error) {
	snapshot, ok := settings["runtimeController"].(map[string]any)
	if !ok {
		return fallback, "", nil
	}
	address, _ := snapshot["controller"].(string)
	secret, _ := snapshot["secret"].(string)
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return "", "", fmt.Errorf("invalid runtime controller address")
	}
	switch host {
	case "0.0.0.0", "*":
		host = "127.0.0.1"
	case "::":
		host = "::1"
	}
	endpoint := url.URL{Scheme: "http", Host: net.JoinHostPort(host, port), Path: "/version"}
	return endpoint.String(), secret, nil
}
