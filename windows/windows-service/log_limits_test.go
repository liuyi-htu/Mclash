package main

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"unicode/utf8"
)

func TestBoundedLogHugeWritesAndConcurrentAppends(t *testing.T) {
	path := filepath.Join(t.TempDir(), "test.log")
	if err := os.WriteFile(path, []byte(strings.Repeat("old", maxLogBytes)), 0o644); err != nil {
		t.Fatal(err)
	}
	data := []byte(strings.Repeat("中", maxLogBytes) + "latest\n")
	if err := appendBoundedLog(path, data); err != nil {
		t.Fatal(err)
	}
	result, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(result) > maxLogBytes || !utf8.Valid(result) || !strings.HasSuffix(string(result), "latest\n") {
		t.Fatal("oversize write did not retain bounded UTF-8 tail")
	}
	var workers sync.WaitGroup
	for i := 0; i < 4; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			for j := 0; j < 100; j++ {
				if err := appendBoundedLog(path, []byte(strings.Repeat("line\n", 400))); err != nil {
					t.Error(err)
					return
				}
			}
		}()
	}
	workers.Wait()
	if err := appendBoundedLog(path, []byte("final marker\n")); err != nil {
		t.Fatal(err)
	}
	result, err = os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(result) > maxLogBytes || !strings.HasSuffix(string(result), "final marker\n") {
		t.Fatal("concurrent writes escaped size limit")
	}
}
