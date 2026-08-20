package main

import (
	"os"
	"reflect"
	"testing"
)

func TestActivateCoreUpdateStopsSwapsAndRestarts(t *testing.T) {
	paths, err := resolvePaths(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(paths.MihomoExe, []byte("old"), 0o755); err != nil {
		t.Fatal(err)
	}
	temporary := paths.MihomoExe + ".update"
	if err := os.WriteFile(temporary, []byte("new"), 0o755); err != nil {
		t.Fatal(err)
	}

	var events []string
	stubUpdateServiceLifecycle(t,
		func(appPaths) statusResult { return statusResult{State: "running"} },
		func() error { events = append(events, "stop"); return nil },
		func(appPaths) error { events = append(events, "start"); return nil },
	)

	err = activateCoreUpdate(paths, "mihomo", paths.MihomoExe, temporary, "2.0.0", func(path string) (string, error) {
		events = append(events, "verify")
		data, readErr := os.ReadFile(path)
		if readErr != nil {
			return "", readErr
		}
		if string(data) != "new" {
			t.Fatalf("verified core contents = %q, want new", data)
		}
		return "2.0.0", nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"stop", "verify", "start"}; !reflect.DeepEqual(events, want) {
		t.Fatalf("events = %v, want %v", events, want)
	}
}

func TestActivateCoreUpdateWhileProxyIsStoppedDoesNotStartService(t *testing.T) {
	paths, err := resolvePaths(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(paths.MihomoExe, []byte("old"), 0o755); err != nil {
		t.Fatal(err)
	}
	temporary := paths.MihomoExe + ".update"
	if err := os.WriteFile(temporary, []byte("new"), 0o755); err != nil {
		t.Fatal(err)
	}

	stops, starts := 0, 0
	stubUpdateServiceLifecycle(t,
		func(appPaths) statusResult { return statusResult{State: "stopped"} },
		func() error { stops++; return nil },
		func(appPaths) error { starts++; return nil },
	)

	err = activateCoreUpdate(paths, "mihomo", paths.MihomoExe, temporary, "2.0.0", func(string) (string, error) {
		return "2.0.0", nil
	})
	if err != nil {
		t.Fatal(err)
	}
	data, readErr := os.ReadFile(paths.MihomoExe)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(data) != "new" {
		t.Fatalf("updated core contents = %q, want new", data)
	}
	if stops != 0 || starts != 0 {
		t.Fatalf("service calls: stops=%d starts=%d, want neither", stops, starts)
	}
}

func TestActivateCoreUpdateRollsBackAndRestartsOnVerificationFailure(t *testing.T) {
	paths, err := resolvePaths(t.TempDir(), "")
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(paths.SingBoxExe, []byte("old"), 0o755); err != nil {
		t.Fatal(err)
	}
	temporary := paths.SingBoxExe + ".update"
	if err := os.WriteFile(temporary, []byte("bad"), 0o755); err != nil {
		t.Fatal(err)
	}

	starts := 0
	stubUpdateServiceLifecycle(t,
		func(appPaths) statusResult { return statusResult{State: "running"} },
		func() error { return nil },
		func(appPaths) error { starts++; return nil },
	)

	err = activateCoreUpdate(paths, "sing-box", paths.SingBoxExe, temporary, "2.0.0", func(string) (string, error) {
		return "1.0.0", nil
	})
	if err == nil {
		t.Fatal("expected version verification failure")
	}
	data, readErr := os.ReadFile(paths.SingBoxExe)
	if readErr != nil {
		t.Fatal(readErr)
	}
	if string(data) != "old" {
		t.Fatalf("rolled-back core contents = %q, want old", data)
	}
	if starts != 1 {
		t.Fatalf("proxy starts = %d, want 1", starts)
	}
}

func stubUpdateServiceLifecycle(
	t *testing.T,
	query func(appPaths) statusResult,
	stop func() error,
	start func(appPaths) error,
) {
	t.Helper()
	originalQuery := queryServiceStatus
	originalStop := stopProxyService
	originalStart := startProxyService
	queryServiceStatus = query
	stopProxyService = stop
	startProxyService = start
	t.Cleanup(func() {
		queryServiceStatus = originalQuery
		stopProxyService = originalStop
		startProxyService = originalStart
	})
}
