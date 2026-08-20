package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	serviceName        = "Mclash"
	legacyServiceName  = "MclashMihomo"
	serviceDisplayName = "Mclash Service"
	serviceDescription = "Mclash"
)

type appPaths struct {
	BaseDir       string
	DataDir       string
	ServiceExe    string
	MihomoExe     string
	SingBoxExe    string
	Config        string
	SingBoxConfig string
	Profiles      string
	Logs          string
	ServiceLog    string
	MihomoLog     string
	SingBoxLog    string
	Settings      string
	RuntimeState  string
	LegacyState   string
	ProxyBackup   string
	GeoSite       string
	GeoIP         string
	CountryDB     string
}

func resolvePaths(baseDir, dataDir string) (appPaths, error) {
	if baseDir == "" {
		exe, err := os.Executable()
		if err != nil {
			return appPaths{}, fmt.Errorf("locate service executable: %w", err)
		}
		baseDir = filepath.Dir(exe)
	}
	if dataDir == "" {
		dataDir = filepath.Join(baseDir, "data")
	}
	baseDir, err := filepath.Abs(baseDir)
	if err != nil {
		return appPaths{}, fmt.Errorf("resolve base directory: %w", err)
	}
	dataDir, err = filepath.Abs(dataDir)
	if err != nil {
		return appPaths{}, fmt.Errorf("resolve data directory: %w", err)
	}
	return appPaths{
		BaseDir:       baseDir,
		DataDir:       dataDir,
		ServiceExe:    filepath.Join(baseDir, "MclashService.exe"),
		MihomoExe:     filepath.Join(baseDir, "mihomo.exe"),
		SingBoxExe:    filepath.Join(baseDir, "sing-box.exe"),
		Config:        filepath.Join(dataDir, "config.yaml"),
		SingBoxConfig: filepath.Join(dataDir, "sing-box.json"),
		Profiles:      filepath.Join(dataDir, "profiles"),
		Logs:          filepath.Join(dataDir, "logs"),
		ServiceLog:    filepath.Join(dataDir, "logs", "service.log"),
		MihomoLog:     filepath.Join(dataDir, "logs", "mihomo.log"),
		SingBoxLog:    filepath.Join(dataDir, "logs", "sing-box.log"),
		Settings:      filepath.Join(dataDir, "settings.json"),
		RuntimeState:  filepath.Join(dataDir, "runtime-state.json"),
		LegacyState:   filepath.Join(dataDir, "state.json"),
		GeoSite:       filepath.Join(dataDir, "GeoSite.dat"),
		GeoIP:         filepath.Join(dataDir, "GeoIP.dat"),
		CountryDB:     filepath.Join(dataDir, "Country.mmdb"),
	}, nil
}

func (p appPaths) ensureDataDirs() error {
	for _, dir := range []string{p.DataDir, p.Profiles, p.Logs} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("create %s: %w", dir, err)
		}
	}
	return nil
}

func validateRegularNonEmpty(path, requiredExt string) error {
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("access %s: %w", path, err)
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("%s is not a regular file", path)
	}
	if info.Size() == 0 {
		return fmt.Errorf("%s is empty", path)
	}
	if requiredExt != "" && !strings.EqualFold(filepath.Ext(path), requiredExt) {
		return fmt.Errorf("%s must use the %s extension", path, requiredExt)
	}
	return nil
}
