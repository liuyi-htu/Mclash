package main

import (
	"io"
	"os"
	"sync"
	"unicode/utf8"
)

const maxLogBytes = 512 * 1024
const keepLogBytes = 256 * 1024

var logWriteMutex sync.Mutex

func logTail(data []byte) []byte {
	for len(data) > 0 && !utf8.RuneStart(data[0]) {
		data = data[1:]
	}
	return data
}

// All three writers share this lock, including stdout and stderr from the core.
func appendBoundedLog(path string, data []byte) error {
	logWriteMutex.Lock()
	defer logWriteMutex.Unlock()
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return err
	}
	if len(data) > maxLogBytes {
		data = logTail(data[len(data)-keepLogBytes:])
	}
	if info.Size()+int64(len(data)) > maxLogBytes {
		count := int64(keepLogBytes)
		if remaining := int64(maxLogBytes - len(data)); count > remaining {
			count = remaining
		}
		if count > info.Size() {
			count = info.Size()
		}
		tail := make([]byte, int(count))
		if _, err = file.ReadAt(tail, info.Size()-count); err != nil && err != io.EOF {
			return err
		}
		tail = logTail(tail)
		if err = file.Truncate(0); err != nil {
			return err
		}
		if _, err = file.Seek(0, io.SeekStart); err != nil {
			return err
		}
		if _, err = file.Write(tail); err != nil {
			return err
		}
	}
	if _, err = file.Seek(0, io.SeekEnd); err != nil {
		return err
	}
	_, err = file.Write(data)
	return err
}
