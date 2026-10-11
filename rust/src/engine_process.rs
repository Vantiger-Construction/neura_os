//! Owned child environment and process handles. Only Windows is exposed by the
//! production C ABI; the portable backend exists to exercise real child tests.

use std::path::PathBuf;

/// Trusted native launch plan, never populated from Flutter text or a URL.
pub(crate) struct SpawnSpec {
    pub executable: PathBuf,
    pub arguments: Vec<String>,
    pub environment: Vec<(String, String)>,
}
impl Drop for SpawnSpec {
    fn drop(&mut self) {
        use zeroize::Zeroize;
        for (_, value) in &mut self.environment {
            value.zeroize();
        }
    }
}

#[cfg(not(windows))]
pub(crate) mod platform {
    use super::SpawnSpec;
    use std::{
        path::Path,
        process::{Child, ChildStdout, Command, Stdio},
    };

    pub(crate) struct ChildProcess {
        child: Child,
    }
    pub(crate) fn spawn_plan(executable: &Path, token: &str) -> Command {
        let mut command = Command::new(executable);
        command
            .env_clear()
            .env("NEURA_API_ADDR", "127.0.0.1:0")
            .env("NEURA_API_LAUNCHER_READY", "1")
            .env("NEURA_API_SESSION_TOKEN", token)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        command
    }
    pub(crate) fn spawn(executable: &Path, token: &str) -> Result<(ChildProcess, ChildStdout), ()> {
        let mut child = spawn_plan(executable, token).spawn().map_err(|_| ())?;
        let pipe = child.stdout.take().ok_or(())?;
        Ok((ChildProcess { child }, pipe))
    }
    pub(crate) fn spawn_spec(spec: &SpawnSpec) -> Result<(ChildProcess, ChildStdout), ()> {
        let mut child = Command::new(&spec.executable)
            .args(&spec.arguments)
            .env_clear()
            .envs(spec.environment.iter().map(|(k, v)| (k, v)))
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|_| ())?;
        let pipe = child.stdout.take().ok_or(())?;
        Ok((ChildProcess { child }, pipe))
    }
    impl ChildProcess {
        pub(crate) fn is_running(&mut self) -> bool {
            matches!(self.child.try_wait(), Ok(None))
        }
        pub(crate) fn terminate(&mut self) {
            let _ = self.child.kill();
            let _ = self.child.wait();
        }
    }
    impl Drop for ChildProcess {
        fn drop(&mut self) {
            self.terminate();
        }
    }
}

#[cfg(windows)]
mod platform {
    use super::SpawnSpec;
    use std::{
        ffi::c_void,
        fs::File,
        mem::{size_of, zeroed},
        os::windows::{ffi::OsStrExt, io::FromRawHandle},
        path::Path,
        ptr::{null, null_mut},
    };
    use windows_sys::Win32::{
        Foundation::{
            CloseHandle, SetHandleInformation, GENERIC_READ, GENERIC_WRITE, HANDLE,
            HANDLE_FLAG_INHERIT, INVALID_HANDLE_VALUE, WAIT_TIMEOUT,
        },
        Security::SECURITY_ATTRIBUTES,
        Storage::FileSystem::{
            CreateFileW, FILE_ATTRIBUTE_NORMAL, FILE_SHARE_READ, FILE_SHARE_WRITE, OPEN_EXISTING,
        },
        System::{
            JobObjects::{
                AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation,
                SetInformationJobObject, TerminateJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION,
                JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
            },
            Pipes::CreatePipe,
            SystemInformation::GetWindowsDirectoryW,
            Threading::{
                CreateProcessW, DeleteProcThreadAttributeList, InitializeProcThreadAttributeList,
                ResumeThread, TerminateProcess, UpdateProcThreadAttribute, WaitForSingleObject,
                CREATE_NO_WINDOW, CREATE_SUSPENDED, CREATE_UNICODE_ENVIRONMENT,
                EXTENDED_STARTUPINFO_PRESENT, PROCESS_INFORMATION,
                PROC_THREAD_ATTRIBUTE_HANDLE_LIST, STARTF_USESTDHANDLES, STARTUPINFOEXW,
            },
        },
    };
    use zeroize::Zeroizing;

    struct Handle(HANDLE);
    // Each handle has one owning worker thread and is never concurrently used.
    unsafe impl Send for Handle {}
    impl Drop for Handle {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }
    impl Handle {
        fn checked(handle: HANDLE) -> Result<Self, ()> {
            if handle.is_null() || handle == INVALID_HANDLE_VALUE {
                Err(())
            } else {
                Ok(Self(handle))
            }
        }
        fn into_file(self) -> File {
            let handle = self.0;
            std::mem::forget(self);
            unsafe { File::from_raw_handle(handle) }
        }
    }
    struct Attributes {
        storage: Vec<usize>,
        initialized: bool,
    }
    impl Attributes {
        unsafe fn new(handles: &mut [HANDLE]) -> Result<Self, ()> {
            let mut size = 0;
            InitializeProcThreadAttributeList(null_mut(), 1, 0, &mut size);
            if size == 0 {
                return Err(());
            }
            let mut attributes = Self {
                storage: vec![0; size.div_ceil(size_of::<usize>())],
                initialized: false,
            };
            if InitializeProcThreadAttributeList(attributes.pointer(), 1, 0, &mut size) == 0 {
                return Err(());
            }
            attributes.initialized = true;
            if UpdateProcThreadAttribute(
                attributes.pointer(),
                0,
                PROC_THREAD_ATTRIBUTE_HANDLE_LIST as usize,
                handles.as_mut_ptr().cast::<c_void>(),
                std::mem::size_of_val(handles),
                null_mut(),
                null_mut(),
            ) == 0
            {
                return Err(());
            }
            Ok(attributes)
        }
        fn pointer(
            &mut self,
        ) -> windows_sys::Win32::System::Threading::LPPROC_THREAD_ATTRIBUTE_LIST {
            self.storage.as_mut_ptr().cast()
        }
    }
    impl Drop for Attributes {
        fn drop(&mut self) {
            unsafe {
                if self.initialized {
                    DeleteProcThreadAttributeList(self.pointer());
                }
            }
        }
    }

    pub(crate) struct ChildProcess {
        process: Handle,
        job: Handle,
    }
    impl ChildProcess {
        pub(crate) fn is_running(&mut self) -> bool {
            unsafe { WaitForSingleObject(self.process.0, 0) == WAIT_TIMEOUT }
        }
        pub(crate) fn terminate(&mut self) {
            unsafe {
                // Job ownership prevents descendants/orphans even if the host
                // crashes. Direct termination is a fallback for a failed job call.
                if TerminateJobObject(self.job.0, 1) == 0 {
                    TerminateProcess(self.process.0, 1);
                }
                WaitForSingleObject(self.process.0, 1000);
            }
        }
    }
    impl Drop for ChildProcess {
        fn drop(&mut self) {
            self.terminate();
        }
    }

    pub(crate) fn spawn(executable: &Path, token: &str) -> Result<(ChildProcess, File), ()> {
        spawn_spec(&SpawnSpec {
            executable: executable.to_owned(),
            arguments: Vec::new(),
            environment: vec![
                ("NEURA_API_ADDR".into(), "127.0.0.1:0".into()),
                ("NEURA_API_LAUNCHER_READY".into(), "1".into()),
                ("NEURA_API_SESSION_TOKEN".into(), token.into()),
            ],
        })
    }

    fn quote_argument(value: &str) -> String {
        let mut quoted = String::from("\"");
        let mut slashes = 0;
        for character in value.chars() {
            if character == '\\' {
                slashes += 1;
                continue;
            }
            quoted.extend(std::iter::repeat_n(
                '\\',
                if character == '"' {
                    2 * slashes + 1
                } else {
                    slashes
                },
            ));
            quoted.push(character);
            slashes = 0;
        }
        quoted.extend(std::iter::repeat_n('\\', 2 * slashes));
        quoted.push('"');
        quoted
    }

    pub(crate) fn spawn_spec(spec: &SpawnSpec) -> Result<(ChildProcess, File), ()> {
        let executable = &spec.executable;
        if spec.arguments.iter().any(|a| a.contains('\0'))
            || spec
                .environment
                .iter()
                .any(|(k, v)| k.contains(['\0', '=']) || v.contains('\0'))
        {
            return Err(());
        }
        unsafe {
            let security = SECURITY_ATTRIBUTES {
                nLength: size_of::<SECURITY_ATTRIBUTES>() as u32,
                lpSecurityDescriptor: null_mut(),
                bInheritHandle: 1,
            };
            let (mut read, mut write) = (null_mut(), null_mut());
            if CreatePipe(&mut read, &mut write, &security, 0) == 0 {
                return Err(());
            }
            let read = Handle::checked(read)?;
            let write = Handle::checked(write)?;
            if SetHandleInformation(read.0, HANDLE_FLAG_INHERIT, 0) == 0 {
                return Err(());
            }
            let nul_name: Vec<u16> = "NUL\0".encode_utf16().collect();
            let nul = Handle::checked(CreateFileW(
                nul_name.as_ptr(),
                GENERIC_READ | GENERIC_WRITE,
                FILE_SHARE_READ | FILE_SHARE_WRITE,
                &security,
                OPEN_EXISTING,
                FILE_ATTRIBUTE_NORMAL,
                null_mut(),
            ))?;
            let job = Handle::checked(CreateJobObjectW(null(), null()))?;
            let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = zeroed();
            limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            if SetInformationJobObject(
                job.0,
                JobObjectExtendedLimitInformation,
                (&limits as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            ) == 0
            {
                return Err(());
            }
            let mut handles = [write.0, nul.0];
            let mut attributes = Attributes::new(&mut handles)?;
            let mut startup: STARTUPINFOEXW = zeroed();
            startup.StartupInfo.cb = size_of::<STARTUPINFOEXW>() as u32;
            startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
            startup.StartupInfo.hStdInput = nul.0;
            startup.StartupInfo.hStdOutput = write.0;
            startup.StartupInfo.hStdError = nul.0;
            startup.lpAttributeList = attributes.pointer();
            let mut windows_directory = [0u16; 32768];
            let count = GetWindowsDirectoryW(
                windows_directory.as_mut_ptr(),
                windows_directory.len() as u32,
            ) as usize;
            if count == 0 || count >= windows_directory.len() {
                return Err(());
            }
            let system_root = String::from_utf16(&windows_directory[..count]).map_err(|_| ())?;
            // Allowlist only runtime necessities. Inherited provider keys, URL
            // overrides, RUST_LOG and old session credentials cannot enter.
            let mut entries = Zeroizing::new(spec.environment.clone());
            entries.push(("SystemRoot".into(), system_root));
            entries.sort_by_key(|(key, _)| key.to_ascii_lowercase());
            let mut environment = Zeroizing::new(String::new());
            for (key, value) in entries.iter() {
                environment.push_str(key);
                environment.push('=');
                environment.push_str(value);
                environment.push('\0');
            }
            environment.push('\0');
            let environment = Zeroizing::new(environment.encode_utf16().collect::<Vec<u16>>());
            let application: Vec<u16> = executable
                .as_os_str()
                .encode_wide()
                .chain(Some(0))
                .collect();
            let mut command_line = quote_argument(&executable.to_string_lossy());
            for argument in &spec.arguments {
                command_line.push(' ');
                command_line.push_str(&quote_argument(argument));
            }
            let mut command: Vec<u16> = command_line.encode_utf16().chain(Some(0)).collect();
            let directory: Vec<u16> = executable
                .parent()
                .ok_or(())?
                .as_os_str()
                .encode_wide()
                .chain(Some(0))
                .collect();
            let mut info: PROCESS_INFORMATION = zeroed();
            if CreateProcessW(
                application.as_ptr(),
                command.as_mut_ptr(),
                null(),
                null(),
                1,
                CREATE_UNICODE_ENVIRONMENT
                    | CREATE_NO_WINDOW
                    | CREATE_SUSPENDED
                    | EXTENDED_STARTUPINFO_PRESENT,
                environment.as_ptr().cast(),
                directory.as_ptr(),
                &startup.StartupInfo,
                &mut info,
            ) == 0
            {
                return Err(());
            }
            let process = Handle::checked(info.hProcess)?;
            let thread = Handle::checked(info.hThread)?;
            let mut child = ChildProcess { process, job };
            if AssignProcessToJobObject(child.job.0, child.process.0) == 0
                || ResumeThread(thread.0) == u32::MAX
            {
                TerminateProcess(child.process.0, 1);
                child.terminate();
                return Err(());
            }
            drop(write);
            Ok((child, read.into_file()))
        }
    }
}

pub(crate) use platform::{spawn, spawn_spec, ChildProcess};
