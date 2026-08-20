package main

import (
	"fmt"
	"os"
	"time"

	"golang.org/x/sys/windows/svc"
)

type serviceHandler struct{ paths appPaths }

type persistedState struct {
	MihomoPID int    `json:"mihomoPid"`
	Message   string `json:"message,omitempty"`
}

func (h *serviceHandler) Execute(_ []string, requests <-chan svc.ChangeRequest, changes chan<- svc.Status) (bool, uint32) {
	const accepts = svc.AcceptStop | svc.AcceptShutdown
	changes <- svc.Status{State: svc.StartPending}
	if err := h.paths.ensureDataDirs(); err != nil {
		h.logf("startup failed: %v", err)
		return false, 1
	}
	if err := validateSelectedConfig(h.paths); err != nil {
		h.logf("startup failed: %v", err)
		h.writeState(0, err.Error())
		return false, 2
	}

	process, err := startSelectedCore(h.paths)
	if err != nil {
		h.logf("startup failed: %v", err)
		h.writeState(0, err.Error())
		return false, 3
	}
	h.logf(
		"mihomo started with PID %d: %q -d %q -f %q",
		process.pid(),
		h.paths.MihomoExe,
		h.paths.DataDir,
		h.paths.Config,
	)
	h.writeState(process.pid(), "")
	changes <- svc.Status{State: svc.Running, Accepts: accepts}

	stopping := false
	for {
		select {
		case request := <-requests:
			switch request.Cmd {
			case svc.Interrogate:
				changes <- request.CurrentStatus
			case svc.Stop, svc.Shutdown:
				stopping = true
				changes <- svc.Status{State: svc.StopPending}
				if err := process.stop(); err != nil {
					h.logf("stop warning: %v", err)
				}
				h.writeState(0, "")
				h.logf("service stopped")
				changes <- svc.Status{State: svc.Stopped}
				return false, 0
			}
		case exitErr := <-process.exit:
			if stopping {
				continue
			}
			h.logf("mihomo exited unexpectedly: %v; restarting in 3 seconds", exitErr)
			h.writeState(0, fmt.Sprintf("mihomo exited: %v", exitErr))
			timer := time.NewTimer(3 * time.Second)
			select {
			case request := <-requests:
				timer.Stop()
				if request.Cmd == svc.Stop || request.Cmd == svc.Shutdown {
					changes <- svc.Status{State: svc.StopPending}
					h.writeState(0, "")
					changes <- svc.Status{State: svc.Stopped}
					return false, 0
				}
			case <-timer.C:
			}
			if err := validateSelectedConfig(h.paths); err != nil {
				h.logf("restart cancelled: %v", err)
				h.writeState(0, err.Error())
				return false, 4
			}
			process, err = startSelectedCore(h.paths)
			if err != nil {
				h.logf("restart failed: %v", err)
				h.writeState(0, err.Error())
				return false, 5
			}
			h.logf(
				"mihomo restarted with PID %d: %q -d %q -f %q",
				process.pid(),
				h.paths.MihomoExe,
				h.paths.DataDir,
				h.paths.Config,
			)
			h.writeState(process.pid(), "")
		}
	}
}

func (h *serviceHandler) logf(format string, args ...any) {
	if !debugLoggingEnabled(h.paths) {
		return
	}
	_ = h.paths.ensureDataDirs()
	file, err := os.OpenFile(h.paths.ServiceLog, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer file.Close()
	_, _ = fmt.Fprintf(file, "%s %s\n", time.Now().Format("2006-01-02 15:04:05"), fmt.Sprintf(format, args...))
}

func (h *serviceHandler) writeState(pid int, message string) {
	_ = h.paths.ensureDataDirs()
	_ = writeRuntimeState(h.paths, pid, message)
}
