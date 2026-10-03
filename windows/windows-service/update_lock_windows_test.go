package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCoreUpdateLockIsExclusiveAndReleased(t *testing.T) {
	paths := appPaths{MihomoExe: filepath.Join(t.TempDir(), "mihomo.exe")}
	release, err := acquireCoreUpdateLock(paths)
	if err != nil {
		t.Fatal(err)
	}
	if unexpectedRelease, err := acquireCoreUpdateLock(paths); err == nil {
		unexpectedRelease()
		release()
		t.Fatal("concurrent update acquired the same lock")
	}
	release()
	releaseAgain, err := acquireCoreUpdateLock(paths)
	if err != nil {
		t.Fatal("lock was not released:", err)
	}
	releaseAgain()
	if _, err := os.Stat(paths.MihomoExe + ".update.lock"); !os.IsNotExist(err) {
		t.Fatal("temporary update lock was not removed:", err)
	}
}
