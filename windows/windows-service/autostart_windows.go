package main

import (
	"errors"
	"fmt"
	"syscall"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc/mgr"
)

type autoStartResult struct {
	Installed bool `json:"installed"`
	Enabled   bool `json:"enabled"`
}

func queryServiceAutoStart() autoStartResult {
	managerHandle, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		return autoStartResult{}
	}
	manager := &mgr.Mgr{Handle: managerHandle}
	defer manager.Disconnect()

	serviceNamePtr, err := syscall.UTF16PtrFromString(serviceName)
	if err != nil {
		return autoStartResult{}
	}
	serviceHandle, err := windows.OpenService(
		manager.Handle,
		serviceNamePtr,
		windows.SERVICE_QUERY_CONFIG,
	)
	if err != nil {
		return autoStartResult{}
	}
	service := &mgr.Service{Name: serviceName, Handle: serviceHandle}
	defer service.Close()

	config, err := service.Config()
	if err != nil {
		return autoStartResult{Installed: true}
	}
	return autoStartResult{
		Installed: true,
		Enabled:   config.StartType == mgr.StartAutomatic,
	}
}

func setServiceAutoStart(enabled bool) error {
	manager, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer manager.Disconnect()
	service, err := manager.OpenService(serviceName)
	if err != nil {
		if errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST) {
			return fmt.Errorf("service %s is not installed", serviceName)
		}
		return err
	}
	defer service.Close()
	config, err := service.Config()
	if err != nil {
		return err
	}
	config.DelayedAutoStart = false
	if enabled {
		config.StartType = mgr.StartAutomatic
	} else {
		config.StartType = mgr.StartManual
	}
	if err := service.UpdateConfig(config); err != nil {
		return fmt.Errorf("update service startup type: %w", err)
	}
	return nil
}
