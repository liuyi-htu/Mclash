package main

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

func migrateLegacyData(paths appPaths) error {
	programData := os.Getenv("ProgramData")
	if programData == "" {
		return nil
	}
	legacyDir, err := filepath.Abs(filepath.Join(programData, "Mclash"))
	if err != nil {
		return fmt.Errorf("resolve legacy data directory: %w", err)
	}
	targetDir, err := filepath.Abs(paths.DataDir)
	if err != nil {
		return fmt.Errorf("resolve installation data directory: %w", err)
	}
	if strings.EqualFold(filepath.Clean(legacyDir), filepath.Clean(targetDir)) {
		return nil
	}
	info, err := os.Stat(legacyDir)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("access legacy data directory: %w", err)
	}
	if !info.IsDir() {
		return fmt.Errorf("legacy data path is not a directory: %s", legacyDir)
	}
	if err := os.MkdirAll(targetDir, 0o755); err != nil {
		return fmt.Errorf("create installation data directory: %w", err)
	}

	err = filepath.WalkDir(legacyDir, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative, err := filepath.Rel(legacyDir, path)
		if err != nil || relative == "." {
			return err
		}
		destination := filepath.Join(targetDir, relative)
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("legacy data contains an unsupported symbolic link: %s", path)
		}
		if entry.IsDir() {
			return os.MkdirAll(destination, 0o755)
		}
		if !entry.Type().IsRegular() {
			return fmt.Errorf("legacy data contains an unsupported file: %s", path)
		}
		if isPackagedGeoData(entry.Name()) {
			if _, statErr := os.Stat(destination); statErr == nil {
				return nil
			}
		}
		return copyMigratedFile(path, destination)
	})
	if err != nil {
		return fmt.Errorf("migrate legacy data: %w", err)
	}
	if err := os.RemoveAll(legacyDir); err != nil {
		return fmt.Errorf("remove migrated legacy data: %w", err)
	}
	return nil
}

func isPackagedGeoData(name string) bool {
	switch strings.ToLower(name) {
	case "geosite.dat", "geoip.dat", "country.mmdb":
		return true
	default:
		return false
	}
}

func copyMigratedFile(source, destination string) error {
	if err := os.MkdirAll(filepath.Dir(destination), 0o755); err != nil {
		return err
	}
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()
	temporary := destination + ".migration"
	output, err := os.OpenFile(temporary, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	_, copyErr := io.Copy(output, input)
	closeErr := output.Close()
	if copyErr != nil {
		_ = os.Remove(temporary)
		return copyErr
	}
	if closeErr != nil {
		_ = os.Remove(temporary)
		return closeErr
	}
	if err := os.Remove(destination); err != nil && !os.IsNotExist(err) {
		_ = os.Remove(temporary)
		return err
	}
	if err := os.Rename(temporary, destination); err != nil {
		_ = os.Remove(temporary)
		return err
	}
	return nil
}
