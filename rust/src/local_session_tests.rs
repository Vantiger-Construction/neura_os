use super::*;
use std::io::{BufRead, BufReader};

#[test]
fn invalidation_clears_content_and_rejects_late_results() {
    let state = State::new();
    let old = state.invalidate(STARTING);
    assert!(state.publish(
        old,
        IDLE,
        Some(Zeroizing::new("private session text".into()))
    ));
    state.invalidate(BLOCKED);
    assert!(!state.publish(old, IDLE, Some(Zeroizing::new("late reply".into()))));
    let snapshot = state.0.lock().unwrap();
    assert_eq!(snapshot.status, BLOCKED);
    assert!(snapshot.reply.is_none());
}

#[test]
fn unsupported_and_safety_block_never_create_text_grants() {
    let mut owner = Launcher::new();
    assert_eq!(owner.start(None), UNAVAILABLE);
    assert!(owner.active.is_none());
    owner.block();
    assert_eq!(owner.start(None), BLOCKED);
    owner.stop();
    assert_eq!(owner.state.status(), BLOCKED);
    assert!(owner.active.is_none());
}

#[test]
fn one_turn_no_waiting_queue_and_stop_revokes() {
    let mut owner = Launcher::new();
    let (cancel, _) = watch::channel(false);
    let (input, mut messages) = mpsc::channel(1);
    let grant = LocalTextGrant::approve_session_text();
    owner.active = Some(Active {
        cancel,
        input,
        grant: grant.clone(),
        worker: thread::spawn(|| {}),
    });
    let epoch = owner.state.invalidate(IDLE);
    assert!(!owner.submit(""));
    assert!(!owner.submit(&"x".repeat(MAX_INPUT_BYTES + 1)));
    assert!(owner.submit("first"));
    assert!(!owner.submit("second"));
    // Even a spurious idle state cannot grow the one-item channel.
    owner.state.publish(epoch, IDLE, None);
    assert!(!owner.submit("second"));
    assert_eq!(messages.try_recv().unwrap().as_str(), "first");
    owner.state.publish(
        epoch,
        IDLE,
        Some(Zeroizing::new("reply waiting for UI".into())),
    );
    assert!(!owner.submit("third"));
    owner.stop();
    assert!(!grant.is_active());
    assert!(owner.active.is_none());
    assert!(owner.state.0.lock().unwrap().reply.is_none());
}

#[test]
fn trusted_plan_has_only_fixed_control_arguments_and_allowlisted_environment() {
    let config = Configuration {
        powershell: PathBuf::from("trusted powershell"),
        script: PathBuf::from("app scripts/start.ps1"),
        assets: PathBuf::from("local assets"),
        window: 123,
    };
    let token = "a".repeat(64);
    let plan = config.plan(&token, &PathBuf::from("temporary runtime"));
    assert!(plan.arguments.contains(&"-NoProfile".into()));
    assert!(plan.arguments.contains(&"-NativeOwner".into()));
    assert!(!plan.arguments.iter().any(|arg| arg.contains(&token)));
    let keys: Vec<_> = plan
        .environment
        .iter()
        .map(|(key, _)| key.as_str())
        .collect();
    assert_eq!(
        keys,
        [
            "NEURA_LOCAL_SESSION_TOKEN",
            "NEURA_LOCAL_APP_WINDOW",
            "NEURA_LOCAL_ASSETS_ROOT",
            "NEURA_LOCAL_RUNTIME_ROOT",
            "OS",
            "TEMP",
            "TMP"
        ]
    );
}

#[test]
fn bounded_receipt_refuses_arbitrary_hosts_and_malformed_output() {
    assert!(read_ready(&b"NEURA_IPC_READY 127.0.0.1:42\n"[..]).is_ok());
    for bytes in [
        &b"NEURA_IPC_READY 10.0.0.1:42\n"[..],
        &b"NEURA_IPC_READY localhost:42\n"[..],
        &b"NEURA_IPC_READY 127.0.0.1:0\n"[..],
        &b"prompt: secret\n"[..],
        &b"NEURA_IPC_READY 127.0.0.1:42\r\n"[..],
        &b"no newline"[..],
    ] {
        assert!(read_ready(bytes).is_err());
    }
    assert!(read_ready(&vec![b'x'; 100][..]).is_err());
}

#[cfg(not(windows))]
#[test]
fn generic_spawn_is_owned_and_reaped_without_inherited_environment() {
    let plan = process::SpawnSpec {
        executable: PathBuf::from("/bin/sh"),
        arguments: vec![
            "-c".into(),
            "printf '%s\\n' \"${PATH_OVERRIDE-unset}\"; exec /bin/sleep 60".into(),
        ],
        environment: vec![("ONLY_APPROVED".into(), "1".into())],
    };
    let (mut child, pipe) = process::spawn_spec(&plan).unwrap();
    let mut line = String::new();
    BufReader::new(pipe).read_line(&mut line).unwrap();
    assert_eq!(line.trim(), "unset");
    assert!(child.is_running());
    child.terminate();
    assert!(!child.is_running());
}

#[cfg(windows)]
#[test]
fn native_parent_job_terminates_descendants() {
    use windows_sys::Win32::{
        Foundation::{CloseHandle, WAIT_TIMEOUT},
        System::{
            SystemInformation::GetWindowsDirectoryW,
            Threading::{OpenProcess, WaitForSingleObject},
        },
    };
    let mut buffer = [0u16; 32768];
    let count = unsafe { GetWindowsDirectoryW(buffer.as_mut_ptr(), buffer.len() as u32) } as usize;
    assert!(count > 0 && count < buffer.len());
    let executable = PathBuf::from(String::from_utf16(&buffer[..count]).unwrap())
        .join("System32/WindowsPowerShell/v1.0/powershell.exe");
    let command = "$s = [Diagnostics.ProcessStartInfo]::new(); $s.FileName = (Join-Path $PSHOME 'powershell.exe'); $s.UseShellExecute = $false; $s.CreateNoWindow = $true; $s.Arguments = '-NoLogo -NoProfile -NonInteractive -Command Start-Sleep -Seconds 60'; $p = [Diagnostics.Process]::Start($s); [Console]::Out.Write(\"$($p.Id)`n\"); [Console]::Out.Flush(); Start-Sleep -Seconds 60";
    let plan = process::SpawnSpec {
        executable,
        arguments: vec![
            "-NoLogo".into(),
            "-NoProfile".into(),
            "-NonInteractive".into(),
            "-Command".into(),
            command.into(),
        ],
        environment: Vec::new(),
    };
    let (mut child, pipe) = process::spawn_spec(&plan).unwrap();
    let mut line = String::new();
    BufReader::new(pipe).read_line(&mut line).unwrap();
    let pid: u32 = line.trim().parse().unwrap();
    let handle = unsafe { OpenProcess(0x00100000, 0, pid) };
    assert!(!handle.is_null());
    assert_eq!(unsafe { WaitForSingleObject(handle, 0) }, WAIT_TIMEOUT);
    child.terminate();
    assert!(!child.is_running());
    assert_ne!(unsafe { WaitForSingleObject(handle, 3000) }, WAIT_TIMEOUT);
    unsafe {
        CloseHandle(handle);
    }
}
