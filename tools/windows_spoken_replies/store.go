package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
)

func savePreferences(path string, commit func(string, string, bool) error) error {
	data, err := os.ReadFile(path)
	existed := !errors.Is(err, os.ErrNotExist)
	if err != nil {
		if existed {
			return err
		}
		data = []byte("{}")
	}
	updated, err := enableReplies(data)
	if err != nil || bytes.Equal(data, updated) {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".neura-voice-*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	_, err = file.Write(updated)
	if err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return commit(path, file.Name(), existed)
}
