package main

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

func TestReadinessRequiresHealthyControllerAndTargetVersion(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte(`{"version":"v2.0.0"}`)) }))
	defer server.Close()
	oldURL, oldTimeout, oldInterval, oldQuery := coreControllerURL, coreReadinessTimeout, coreReadinessPollInterval, queryServiceStatus
	t.Cleanup(func() {
		coreControllerURL, coreReadinessTimeout, coreReadinessPollInterval, queryServiceStatus = oldURL, oldTimeout, oldInterval, oldQuery
	})
	coreControllerURL, coreReadinessTimeout, coreReadinessPollInterval = server.URL, 20*time.Millisecond, time.Millisecond
	status := statusResult{State: "running", MihomoPID: 123}
	queryServiceStatus = func(appPaths) statusResult { return status }
	if err := waitForCoreReady(appPaths{}, "2.0.0"); err != nil {
		t.Fatal(err)
	}
	if err := waitForCoreReady(appPaths{}, "3.0.0"); err == nil {
		t.Fatal("unexpected controller version accepted")
	}
	status.MihomoPID = 0
	if err := waitForCoreReady(appPaths{}, "2.0.0"); err == nil {
		t.Fatal("missing supervised PID accepted")
	}
	status.State = "stopped"
	if err := waitForCoreReady(appPaths{}, "2.0.0"); err == nil {
		t.Fatal("stopped service accepted")
	}
}
