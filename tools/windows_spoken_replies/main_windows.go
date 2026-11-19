package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"unsafe"

	"golang.org/x/sys/windows"
)

const appMutex = `Local\NeuraCompanionPrimaryInstance-v1`

var replaceFile = windows.NewLazySystemDLL("kernel32.dll").NewProc("ReplaceFileW")

func withAppClosed(action func() error) error {
	// The reviewed Windows runner checks mutex existence before loading
	// Flutter. Reserve the identical name for the whole preferences change.
	name, _ := windows.UTF16PtrFromString(appMutex)
	handle, err := windows.CreateMutex(nil, false, name)
	if handle != 0 {
		defer windows.CloseHandle(handle)
	}
	if errors.Is(err, windows.ERROR_ALREADY_EXISTS) {
		return errors.New("Neura is already open. Close her window, then open START_NEURA again.")
	}
	if err != nil {
		return errors.New("Could not check whether Neura is open.")
	}
	return action()
}

func commitWindows(path, tempPath string, existed bool) error {
	target, err := windows.UTF16PtrFromString(path)
	if err != nil {
		return err
	}
	temp, err := windows.UTF16PtrFromString(tempPath)
	if err != nil {
		return err
	}
	if !existed {
		return windows.MoveFile(temp, target)
	}
	// Replace in the same directory, retaining the existing file's ACL.
	ok, _, failure := replaceFile.Call(uintptr(unsafe.Pointer(target)), uintptr(unsafe.Pointer(temp)), 0, 0, 0, 0)
	if ok == 0 {
		return failure
	}
	return nil
}

func launch() error {
	self, err := os.Executable()
	if err != nil {
		return errors.New("Could not locate the launcher.")
	}
	dir := filepath.Join(filepath.Dir(self), "Windows")
	app := filepath.Join(dir, "neuro_companion.exe")
	for _, required := range []string{app, filepath.Join(dir, "data", "app.so")} {
		if info, err := os.Stat(required); err != nil || !info.Mode().IsRegular() {
			return errors.New("Extract the whole ZIP first. Keep START_NEURA beside the Windows folder.")
		}
	}
	if err := withAppClosed(func() error {
		roaming, err := windows.KnownFolderPath(windows.FOLDERID_RoamingAppData, 0)
		if err != nil {
			return errors.New("Windows could not locate your Neura settings.")
		}
		path := filepath.Join(roaming, "com.neurocompanion", "Neura", "shared_preferences.json")
		if err := savePreferences(path, commitWindows); err != nil {
			return errors.New("Could not enable spoken replies. Open Windows\\neuro_companion.exe and select After reply in Neura's Voice settings.")
		}
		return nil
	}); err != nil {
		return err
	}
	cmd := exec.Command(app)
	cmd.Dir = dir
	if err := cmd.Start(); err != nil {
		return errors.New("Windows could not start Neura. Extract the whole ZIP into a writable folder and try again.")
	}
	return cmd.Process.Release()
}

func main() {
	if err := launch(); err != nil {
		title, _ := windows.UTF16PtrFromString("Start Neura")
		message, _ := windows.UTF16PtrFromString(err.Error())
		windows.MessageBox(0, message, title, windows.MB_OK|windows.MB_ICONERROR)
		os.Exit(1)
	}
}
