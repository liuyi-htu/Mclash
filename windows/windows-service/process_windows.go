package main

import (
	"fmt"
	"os"
	"os/exec"
	"sync"
	"syscall"
	"time"
)

func selectedCore(paths appPaths) string {
	if readSettings(paths)["coreType"] == "sing-box" {
		return "sing-box"
	}
	return "mihomo"
}

func debugLoggingEnabled(paths appPaths) bool {
	return readSettings(paths)["debugLoggingEnabled"] == true
}

func validateSelectedConfig(paths appPaths) error {
	if selectedCore(paths) == "sing-box" {
		if err := validateRegularNonEmpty(paths.SingBoxExe, ".exe"); err != nil {
			return err
		}
		if err := validateRegularNonEmpty(paths.SingBoxConfig, ".json"); err != nil {
			return err
		}
		cmd := exec.Command(paths.SingBoxExe, "check", "-c", paths.SingBoxConfig)
		cmd.Dir = paths.DataDir
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		if output, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("sing-box configuration check failed: %w: %s", err, string(output))
		}
		return nil
	}
	return validateMihomoConfig(paths)
}

func startSelectedCore(paths appPaths) (*mihomoProcess, error) {
	if selectedCore(paths) == "sing-box" {
		return startCoreProcess(paths, paths.SingBoxExe, paths.SingBoxLog, paths.DataDir, []string{"run", "-c", paths.SingBoxConfig})
	}
	return startMihomo(paths)
}

func startCoreProcess(paths appPaths, executable, logPath, workingDir string, args []string) (*mihomoProcess, error) {
	logWriter := &debugLogWriter{paths: paths, path: logPath}
	cmd := exec.Command(executable, args...)
	cmd.Dir, cmd.Stdout, cmd.Stderr = workingDir, logWriter, logWriter
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	p := &mihomoProcess{cmd: cmd, exit: make(chan error, 1), logWriter: logWriter}
	go func() {
		err := cmd.Wait()
		_ = logWriter.Close()
		p.exit <- err
	}()
	return p, nil
}

type debugLogWriter struct {
	paths appPaths
	path  string
	mu    sync.Mutex
	file  *os.File
}

func (w *debugLogWriter) Write(data []byte) (int, error) {
	if !debugLoggingEnabled(w.paths) {
		return len(data), nil
	}
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.file == nil {
		if err := w.paths.ensureDataDirs(); err != nil {
			return 0, err
		}
		file, err := os.OpenFile(w.path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
		if err != nil {
			return 0, fmt.Errorf("open core log: %w", err)
		}
		w.file = file
	}
	return w.file.Write(data)
}

func (w *debugLogWriter) Close() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.file == nil {
		return nil
	}
	err := w.file.Close()
	w.file = nil
	return err
}

type mihomoProcess struct {
	cmd       *exec.Cmd
	exit      chan error
	logWriter *debugLogWriter
	stopOnce  sync.Once
}

func validateMihomoConfig(paths appPaths) error {
	if err := validateRegularNonEmpty(paths.MihomoExe, ".exe"); err != nil {
		return err
	}
	if err := validateRegularNonEmpty(paths.Config, ".yaml"); err != nil {
		return err
	}
	for _, geodata := range []string{paths.GeoSite, paths.GeoIP, paths.CountryDB} {
		if err := validateRegularNonEmpty(geodata, ""); err != nil {
			return fmt.Errorf("required geodata is unavailable: %w", err)
		}
	}
	cmd := exec.Command(paths.MihomoExe, "-t", "-d", paths.DataDir, "-f", paths.Config)
	cmd.Dir = paths.DataDir
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("mihomo configuration check failed: %w: %s", err, string(output))
	}
	return nil
}

func startMihomo(paths appPaths) (*mihomoProcess, error) {
	return startCoreProcess(paths, paths.MihomoExe, paths.MihomoLog, paths.DataDir, []string{"-d", paths.DataDir, "-f", paths.Config})
}

func (p *mihomoProcess) pid() int {
	if p == nil || p.cmd == nil || p.cmd.Process == nil {
		return 0
	}
	return p.cmd.Process.Pid
}

func (p *mihomoProcess) stop() error {
	if p == nil || p.cmd == nil || p.cmd.Process == nil {
		return nil
	}
	var result error
	p.stopOnce.Do(func() {
		// Ask the child to terminate cleanly first. Windows may not support the
		// interrupt signal for a hidden process, so a bounded kill is the fallback.
		_ = p.cmd.Process.Signal(os.Interrupt)
		select {
		case <-p.exit:
			return
		case <-time.After(5 * time.Second):
		}
		if err := p.cmd.Process.Kill(); err != nil {
			result = fmt.Errorf("force stop mihomo: %w", err)
			return
		}
		select {
		case <-p.exit:
		case <-time.After(2 * time.Second):
			result = fmt.Errorf("timed out waiting for mihomo to stop")
		}
	})
	return result
}
