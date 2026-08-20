package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"
)

type statusResult struct {
	Installed bool   `json:"installed"`
	State     string `json:"state"`
	MihomoPID int    `json:"mihomoPid"`
	Message   string `json:"message"`
}

func installService(paths appPaths) error {
	manager, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer manager.Disconnect()
	if err := removeServiceByName(manager, legacyServiceName); err != nil {
		return fmt.Errorf("remove legacy service: %w", err)
	}
	args := []string{"run-service", "--base", paths.BaseDir, "--data-dir", paths.DataDir}
	service, err := manager.OpenService(serviceName)
	if err == nil {
		defer service.Close()
		status, statusErr := service.Query()
		if statusErr != nil {
			return fmt.Errorf("read existing service status: %w", statusErr)
		}
		if status.State != svc.Stopped {
			if stopErr := stopServiceHandle(service); stopErr != nil {
				return fmt.Errorf("stop existing service before migration: %w", stopErr)
			}
		}
		if migrationErr := migrateLegacyData(paths); migrationErr != nil {
			return migrationErr
		}
		if dataErr := paths.ensureDataDirs(); dataErr != nil {
			return dataErr
		}
		config, configErr := service.Config()
		if configErr != nil {
			return fmt.Errorf("read existing service configuration: %w", configErr)
		}
		config.DisplayName = serviceDisplayName
		config.Description = serviceDescription
		config.BinaryPathName = joinWindowsArgs(append(
			[]string{paths.ServiceExe},
			args...,
		))
		if updateErr := service.UpdateConfig(config); updateErr != nil {
			return fmt.Errorf("update existing service configuration: %w", updateErr)
		}
		_ = os.Remove(filepath.Join(paths.BaseDir, "mihomoService.exe"))
		return nil
	}
	if err := migrateLegacyData(paths); err != nil {
		return err
	}
	if err := paths.ensureDataDirs(); err != nil {
		return err
	}
	service, err = manager.CreateService(serviceName, paths.ServiceExe, mgr.Config{
		DisplayName: serviceDisplayName,
		Description: serviceDescription,
		StartType:   mgr.StartManual,
	}, args...)
	if err != nil {
		return err
	}
	if err := service.Close(); err != nil {
		return err
	}
	_ = os.Remove(filepath.Join(paths.BaseDir, "mihomoService.exe"))
	return nil
}

func uninstallService() error {
	manager, err := mgr.Connect()
	if err != nil {
		return err
	}
	defer manager.Disconnect()
	for _, name := range []string{serviceName, legacyServiceName} {
		if err := removeServiceByName(manager, name); err != nil {
			return err
		}
	}
	return nil
}

func removeServiceByName(manager *mgr.Mgr, name string) error {
	service, err := manager.OpenService(name)
	if err != nil {
		if errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST) {
			return nil
		}
		return err
	}
	defer service.Close()
	_ = stopServiceHandle(service)
	return service.Delete()
}

func startService(paths appPaths) error {
	if err := paths.ensureDataDirs(); err != nil {
		return err
	}
	if err := validateSelectedConfig(paths); err != nil {
		return err
	}
	manager, service, err := openService()
	if err != nil {
		return err
	}
	defer manager.Disconnect()
	defer service.Close()
	if err := service.Start(); err != nil {
		return err
	}
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		status, err := service.Query()
		if err != nil {
			return err
		}
		if status.State == svc.Running {
			return nil
		}
		if status.State == svc.Stopped {
			return fmt.Errorf("service stopped before reaching the running state")
		}
		time.Sleep(250 * time.Millisecond)
	}
	return fmt.Errorf("timed out waiting for service to start")
}

func stopService() error {
	manager, service, err := openService()
	if err != nil {
		return err
	}
	defer manager.Disconnect()
	defer service.Close()
	return stopServiceHandle(service)
}

func restartService(paths appPaths) error {
	if err := stopService(); err != nil && !strings.Contains(strings.ToLower(err.Error()), "not active") {
		return err
	}
	return startService(paths)
}

func openService() (*mgr.Mgr, *mgr.Service, error) {
	manager, err := mgr.Connect()
	if err != nil {
		return nil, nil, err
	}
	service, err := manager.OpenService(serviceName)
	if err != nil {
		manager.Disconnect()
		return nil, nil, err
	}
	return manager, service, nil
}

func stopServiceHandle(service *mgr.Service) error {
	status, err := service.Control(svc.Stop)
	if err != nil {
		return err
	}
	deadline := time.Now().Add(15 * time.Second)
	for status.State != svc.Stopped && time.Now().Before(deadline) {
		time.Sleep(250 * time.Millisecond)
		status, err = service.Query()
		if err != nil {
			return err
		}
	}
	if status.State != svc.Stopped {
		return fmt.Errorf("timed out waiting for service to stop")
	}
	return nil
}

func queryStatus(paths appPaths) statusResult {
	result := statusResult{State: "unknown"}
	managerHandle, err := windows.OpenSCManager(nil, nil, windows.SC_MANAGER_CONNECT)
	if err != nil {
		result.Message = err.Error()
		return result
	}
	manager := &mgr.Mgr{Handle: managerHandle}
	defer manager.Disconnect()
	serviceNamePtr, _ := syscall.UTF16PtrFromString(serviceName)
	serviceHandle, err := windows.OpenService(
		manager.Handle,
		serviceNamePtr,
		windows.SERVICE_QUERY_STATUS,
	)
	if err != nil {
		if errors.Is(err, windows.ERROR_SERVICE_DOES_NOT_EXIST) {
			result.State = "not_installed"
			return result
		}
		result.Message = err.Error()
		return result
	}
	service := &mgr.Service{Name: serviceName, Handle: serviceHandle}
	defer service.Close()
	result.Installed = true
	status, err := service.Query()
	if err != nil {
		result.Message = err.Error()
		return result
	}
	result.State = serviceStateName(status.State)
	saved := readRuntimeState(paths)
	result.MihomoPID = saved.MihomoPID
	result.Message = saved.Message
	if result.State != "running" {
		result.MihomoPID = 0
	}
	return result
}

func clearRuntimeMessage(paths appPaths) error {
	saved := readRuntimeState(paths)
	return writeRuntimeState(paths, saved.MihomoPID, "")
}

func serviceStateName(state svc.State) string {
	switch state {
	case svc.Running:
		return "running"
	case svc.Stopped:
		return "stopped"
	case svc.StartPending:
		return "start_pending"
	case svc.StopPending:
		return "stop_pending"
	case svc.Paused, svc.PausePending, svc.ContinuePending:
		return "paused"
	default:
		return "unknown"
	}
}
