package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	"golang.org/x/sys/windows"
)

func readJSONMap(path string) (map[string]any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	value := map[string]any{}
	if err := json.Unmarshal(data, &value); err != nil {
		return nil, fmt.Errorf("decode %s: %w", path, err)
	}
	return value, nil
}

func readSettings(paths appPaths) map[string]any {
	if settings, err := readJSONMap(paths.Settings); err == nil {
		return settings
	}
	if legacy, err := readJSONMap(paths.LegacyState); err == nil {
		delete(legacy, "mihomoPid")
		delete(legacy, "message")
		return legacy
	}
	return map[string]any{}
}

func readRuntimeState(paths appPaths) persistedState {
	for _, path := range []string{paths.RuntimeState, paths.LegacyState} {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		var saved persistedState
		if json.Unmarshal(data, &saved) == nil {
			return saved
		}
	}
	return persistedState{}
}

func writeJSONAtomic(path string, value any) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0o644); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Sync(); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	from, err := windows.UTF16PtrFromString(temporaryPath)
	if err != nil {
		return err
	}
	to, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	return windows.MoveFileEx(
		from,
		to,
		windows.MOVEFILE_REPLACE_EXISTING|windows.MOVEFILE_WRITE_THROUGH,
	)
}

func writeRuntimeState(paths appPaths, pid int, message string) error {
	return writeJSONAtomic(paths.RuntimeState, persistedState{
		MihomoPID: pid,
		Message:   message,
	})
}
