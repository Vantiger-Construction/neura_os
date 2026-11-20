package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestNativePreferenceCreateAndReplace(t *testing.T) {
	path := filepath.Join(t.TempDir(), "Neura", "shared_preferences.json")
	if err := savePreferences(path, commitWindows); err != nil {
		t.Fatal(err)
	}
	before := []byte(`{"flutter.neura.tts.volume":0.0,"fixture":17}`)
	if err := os.WriteFile(path, before, 0600); err != nil {
		t.Fatal(err)
	}
	if err := savePreferences(path, commitWindows); err != nil {
		t.Fatal(err)
	}
	want, err := enableReplies(before)
	if err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(path)
	if err != nil || string(got) != string(want) {
		t.Fatal("Windows did not replace the settings with the expected values")
	}
}

func TestExistingNeuraMutexBlocksEdits(t *testing.T) {
	err := withAppClosed(func() error {
		err := withAppClosed(func() error {
			t.Fatal("entered the preferences writer with an existing Neura mutex")
			return nil
		})
		if err == nil {
			return errors.New("expected an already-open error")
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}
