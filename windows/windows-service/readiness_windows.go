package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

var (
	coreControllerURL         = "http://127.0.0.1:9090/version"
	coreReadinessTimeout      = 30 * time.Second
	coreReadinessPollInterval = 250 * time.Millisecond
)

// Verify both the supervised PID and the controller, not just the SCM state.
func waitForCoreReady(paths appPaths, wanted string) error {
	client := &http.Client{Timeout: 2 * time.Second, Transport: &http.Transport{Proxy: nil}}
	defer client.CloseIdleConnections()
	deadline := time.Now().Add(coreReadinessTimeout)
	var last error
	for time.Now().Before(deadline) {
		status := queryServiceStatus(paths)
		if status.State != "running" {
			return fmt.Errorf("core service is %s: %s", status.State, status.Message)
		}
		if status.MihomoPID > 0 {
			response, err := client.Get(coreControllerURL)
			if err == nil {
				var version struct {
					Version string `json:"version"`
				}
				err = json.NewDecoder(io.LimitReader(response.Body, 64<<10)).Decode(&version)
				response.Body.Close()
				if response.StatusCode == http.StatusOK && err == nil {
					current, parseErr := normalizeVersion(version.Version)
					if parseErr == nil && (wanted == "" || current == wanted) {
						return nil
					}
					err = fmt.Errorf("controller version %q, expected %q", version.Version, wanted)
				}
			}
			last = err
		}
		time.Sleep(coreReadinessPollInterval)
	}
	return fmt.Errorf("core readiness timed out: %v", last)
}
