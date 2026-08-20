package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const internetSettingsPath = `Software\Microsoft\Windows\CurrentVersion\Internet Settings`

var managedProxyValues = []string{"ProxyEnable", "ProxyServer", "ProxyOverride"}

var internetSetOption = windows.NewLazySystemDLL("wininet.dll").NewProc("InternetSetOptionW")

type proxyRegistryValue struct {
	Type string `json:"type"`
	Data string `json:"data"`
}

type systemProxyBackup struct {
	Original map[string]*proxyRegistryValue
	Owned    map[string]*proxyRegistryValue
}

func decodeSystemProxyBackup(data []byte) (systemProxyBackup, error) {
	raw := map[string]json.RawMessage{}
	if err := json.Unmarshal(data, &raw); err != nil {
		return systemProxyBackup{}, err
	}
	var backup systemProxyBackup
	if original, ok := raw["original"]; ok {
		if err := json.Unmarshal(original, &backup.Original); err != nil {
			return systemProxyBackup{}, err
		}
		if owned, ok := raw["owned"]; ok {
			if err := json.Unmarshal(owned, &backup.Owned); err != nil {
				return systemProxyBackup{}, err
			}
		}
	} else {
		if err := json.Unmarshal(data, &backup.Original); err != nil {
			return systemProxyBackup{}, err
		}
	}
	for _, name := range managedProxyValues {
		if value := backup.Original[name]; value != nil {
			if value.Type == "" || value.Data == "" && !strings.EqualFold(value.Type, "REG_SZ") {
				return systemProxyBackup{}, fmt.Errorf("invalid original proxy value %s", name)
			}
		}
	}
	return backup, nil
}

func restoreSystemProxy(backupPath string) error {
	if backupPath == "" {
		return fmt.Errorf("--proxy-backup is required")
	}
	data, err := os.ReadFile(backupPath)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	backup, err := decodeSystemProxyBackup(data)
	if err != nil {
		return fmt.Errorf("decode system proxy backup: %w", err)
	}
	key, err := registry.OpenKey(
		registry.CURRENT_USER,
		internetSettingsPath,
		registry.QUERY_VALUE|registry.SET_VALUE,
	)
	if err != nil {
		return err
	}
	defer key.Close()

	owned, err := registryProxyIsOwned(key, backup)
	if err != nil {
		return err
	}
	if !owned {
		return os.Remove(backupPath)
	}
	for _, name := range managedProxyValues {
		if err := restoreRegistryValue(key, name, backup.Original[name]); err != nil {
			return err
		}
	}
	_, _, _ = internetSetOption.Call(0, 39, 0, 0)
	_, _, _ = internetSetOption.Call(0, 37, 0, 0)
	return os.Remove(backupPath)
}

func registryProxyIsOwned(key registry.Key, backup systemProxyBackup) (bool, error) {
	server, _, err := key.GetStringValue("ProxyServer")
	if err != nil && !errors.Is(err, registry.ErrNotExist) {
		return false, err
	}
	if expected := backup.Owned["ProxyServer"]; expected != nil {
		return strings.HasPrefix(expected.Data, "127.0.0.1:") && server == expected.Data, nil
	}
	enabled, _, enabledErr := key.GetIntegerValue("ProxyEnable")
	if enabledErr != nil && !errors.Is(enabledErr, registry.ErrNotExist) {
		return false, enabledErr
	}
	return enabled == 1 && regexp.MustCompile(`^127\.0\.0\.1:\d+$`).MatchString(server), nil
}

func restoreRegistryValue(
	key registry.Key,
	name string,
	value *proxyRegistryValue,
) error {
	if value == nil {
		err := key.DeleteValue(name)
		if errors.Is(err, registry.ErrNotExist) {
			return nil
		}
		return err
	}
	switch strings.ToUpper(value.Type) {
	case "REG_SZ":
		return key.SetStringValue(name, value.Data)
	case "REG_EXPAND_SZ":
		return key.SetExpandStringValue(name, value.Data)
	case "REG_DWORD":
		normalized := strings.TrimSpace(strings.ToLower(value.Data))
		base := 10
		if strings.HasPrefix(normalized, "0x") {
			base = 16
			normalized = strings.TrimPrefix(normalized, "0x")
		}
		number, err := strconv.ParseUint(normalized, base, 32)
		if err != nil {
			return fmt.Errorf("parse %s: %w", name, err)
		}
		return key.SetDWordValue(name, uint32(number))
	default:
		return fmt.Errorf("unsupported registry type %q for %s", value.Type, name)
	}
}
