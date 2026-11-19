package main

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestSaveOnFirstAndSecondLaunch(t *testing.T) {
	path := filepath.Join(t.TempDir(), "Neura", "shared_preferences.json")
	writes := 0
	commit := func(to, from string, existed bool) error {
		writes++
		if existed || filepath.Dir(to) != filepath.Dir(from) {
			t.Fatal("first launch did not stage beside a new preferences file")
		}
		return os.Rename(from, to)
	}
	for i := 0; i < 2; i++ {
		if err := savePreferences(path, commit); err != nil {
			t.Fatal(err)
		}
	}
	if writes != 1 {
		t.Fatalf("expected one write, got %d", writes)
	}
}

func TestSettingsSurviveWriteFailure(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "shared_preferences.json")
	before := []byte(`{"flutter.neura.tts.volume":0.0,"fixture":17}`)
	if err := os.WriteFile(path, before, 0600); err != nil {
		t.Fatal(err)
	}
	failure := errors.New("simulated replacement failure")
	err := savePreferences(path, func(to, from string, existed bool) error {
		if !existed {
			t.Fatal("expected update of existing preferences")
		}
		return failure
	})
	if !errors.Is(err, failure) {
		t.Fatal("replacement failure was hidden")
	}
	after, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(before, after) {
		t.Fatal("existing preferences changed on failure")
	}
	entries, err := os.ReadDir(dir)
	if err != nil || len(entries) != 1 {
		t.Fatal("staged preferences left behind")
	}
}
