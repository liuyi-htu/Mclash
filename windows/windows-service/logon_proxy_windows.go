package main

import (
	"encoding/json"
	"fmt"
	"golang.org/x/sys/windows/registry"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"time"
)

func proxyPortFromConfig(content string) (int, error) {
	for _, name := range []string{"mixed-port", "port"} {
		pattern := regexp.MustCompile(`(?m)^` + name + `:\s*["']?(\d+)["']?\s*(?:#.*)?$`)
		match := pattern.FindStringSubmatch(content)
		if len(match) == 2 {
			port, err := strconv.Atoi(match[1])
			if err == nil && port > 0 && port <= 65535 {
				return port, nil
			}
		}
	}
	return 0, fmt.Errorf("configuration has no valid HTTP proxy port")
}

func syncUserProxy(paths appPaths) error {
	if !queryServiceAutoStart().Enabled {
		return nil
	}
	if readSettings(paths)["networkMode"] == "tun" {
		return restoreSystemProxy(paths.ProxyBackup)
	}
	deadline := time.Now().Add(60 * time.Second)
	for time.Now().Before(deadline) {
		status := queryStatus(paths)
		if status.State == "running" && status.MihomoPID > 0 {
			break
		}
		time.Sleep(time.Second)
	}
	if err := waitForCoreReady(paths, ""); err != nil {
		_ = restoreSystemProxy(paths.ProxyBackup)
		return err
	}
	content, err := os.ReadFile(paths.Config)
	if err != nil {
		return err
	}
	port, err := proxyPortFromConfig(string(content))
	if err != nil {
		return err
	}
	bypass := "localhost;127.*"
	if readSettings(paths)["bypassLanEnabled"] != false {
		bypass = "<local>;" + bypass + ";10.*;192.168.*;169.254.*"
		for i := 16; i <= 31; i++ {
			bypass += fmt.Sprintf(";172.%d.*", i)
		}
	}
	return enableUserSystemProxy(paths.ProxyBackup, port, bypass)
}

func readProxyValues(key registry.Key) (map[string]*proxyRegistryValue, error) {
	values := map[string]*proxyRegistryValue{}
	for _, name := range managedProxyValues {
		_, kind, err := key.GetValue(name, nil)
		if err == registry.ErrNotExist {
			values[name] = nil
			continue
		}
		if err != nil {
			return nil, err
		}
		value := &proxyRegistryValue{}
		switch kind {
		case registry.DWORD:
			number, _, err := key.GetIntegerValue(name)
			if err != nil {
				return nil, err
			}
			value.Type, value.Data = "REG_DWORD", strconv.FormatUint(number, 10)
		case registry.SZ, registry.EXPAND_SZ:
			text, _, err := key.GetStringValue(name)
			if err != nil {
				return nil, err
			}
			value.Type, value.Data = "REG_SZ", text
			if kind == registry.EXPAND_SZ {
				value.Type = "REG_EXPAND_SZ"
			}
		default:
			return nil, fmt.Errorf("unsupported proxy registry type %d", kind)
		}
		values[name] = value
	}
	return values, nil
}

func enableUserSystemProxy(backupPath string, port int, bypass string) error {
	if backupPath == "" {
		return fmt.Errorf("proxy backup path is required")
	}
	key, err := registry.OpenKey(registry.CURRENT_USER, internetSettingsPath, registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		return err
	}
	defer key.Close()
	original, err := readProxyValues(key)
	if err != nil {
		return err
	}
	if data, err := os.ReadFile(backupPath); err == nil {
		old, decodeErr := decodeSystemProxyBackup(data)
		if decodeErr != nil {
			return decodeErr
		}
		owned, checkErr := registryProxyIsOwned(key, old)
		if checkErr != nil {
			return checkErr
		}
		if owned {
			original = old.Original
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	owned := map[string]*proxyRegistryValue{
		"ProxyEnable":   {Type: "REG_DWORD", Data: "1"},
		"ProxyServer":   {Type: "REG_SZ", Data: fmt.Sprintf("127.0.0.1:%d", port)},
		"ProxyOverride": {Type: "REG_SZ", Data: bypass},
	}
	data, err := json.Marshal(map[string]any{"version": 2, "original": original, "owned": owned})
	if err != nil {
		return err
	}
	directory := filepath.Dir(backupPath)
	if err = os.MkdirAll(directory, 0o700); err != nil {
		return err
	}
	if err = os.WriteFile(backupPath+".tmp", data, 0o600); err != nil {
		return err
	}
	if err = os.Rename(backupPath+".tmp", backupPath); err != nil {
		return err
	}
	for _, name := range []string{"ProxyServer", "ProxyOverride", "ProxyEnable"} {
		if err = restoreRegistryValue(key, name, owned[name]); err != nil {
			_ = restoreSystemProxy(backupPath)
			return err
		}
	}
	_, _, _ = internetSetOption.Call(0, 39, 0, 0)
	_, _, _ = internetSetOption.Call(0, 37, 0, 0)
	return nil
}
