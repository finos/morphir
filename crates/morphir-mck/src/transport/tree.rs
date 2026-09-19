//! The adapter's process tree. An adapter may start processes of its own, so
//! terminating only the adapter could leave its children running, holding the
//! pipes open. On Unix the adapter leads a new process group and the whole
//! group is killed; on Windows it is placed in a Job Object that is terminated,
//! and that kills its members when its last handle closes. The adapter never
//! opens a console window on Windows.

use std::process::{Child, Command};
use std::sync::Arc;

#[cfg(unix)]
mod imp {
    use std::process::{Child, Command};

    use rustix::process::{Pid, Signal, kill_process_group};

    pub fn configure(command: &mut Command) {
        use std::os::unix::process::CommandExt as _;
        command.process_group(0);
    }

    pub struct Tree {
        group: Pid,
    }

    impl Tree {
        /// The group was set before the adapter ran anything, so there is no
        /// window in which it can start a process outside it.
        pub fn attach(child: &Child) -> Result<Self, String> {
            Ok(Self {
                group: Pid::from_child(child),
            })
        }

        pub fn kill(&self) {
            // The group may already be gone; that is the goal, not an error.
            let _ = kill_process_group(self.group, Signal::KILL);
        }
    }
}

#[cfg(windows)]
mod imp {
    use std::io;
    use std::os::windows::io::AsRawHandle as _;
    use std::process::{Child, Command};

    use windows_sys::Win32::Foundation::{CloseHandle, HANDLE, INVALID_HANDLE_VALUE};
    use windows_sys::Win32::System::Diagnostics::ToolHelp::{
        CreateToolhelp32Snapshot, TH32CS_SNAPTHREAD, THREADENTRY32, Thread32First, Thread32Next,
    };
    use windows_sys::Win32::System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
        SetInformationJobObject, TerminateJobObject,
    };
    use windows_sys::Win32::System::Threading::{OpenThread, ResumeThread, THREAD_SUSPEND_RESUME};

    /// `CREATE_NO_WINDOW`: a console child gets no console window.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    /// `CREATE_SUSPENDED`: the child runs nothing until it is in its job.
    const CREATE_SUSPENDED: u32 = 0x0000_0004;

    /// The adapter starts suspended, so it cannot start a process of its own
    /// before it is in the job; `attach` resumes it.
    pub fn configure(command: &mut Command) {
        use std::os::windows::process::CommandExt as _;
        command.creation_flags(CREATE_NO_WINDOW | CREATE_SUSPENDED);
    }

    pub struct Tree {
        job: HANDLE,
    }

    // The job handle is only used to terminate and close the job, which the
    // system allows from any thread, concurrently.
    unsafe impl Send for Tree {}
    unsafe impl Sync for Tree {}

    fn failed(what: &str) -> String {
        format!("{what}: {}", io::Error::last_os_error())
    }

    /// Resumes every thread of the suspended process `pid`: its one initial
    /// thread, found through a thread snapshot. Returns how many resumed.
    ///
    /// SAFETY: plain Win32 calls; every handle opened here is closed here.
    unsafe fn resume(pid: u32) -> Result<usize, String> {
        unsafe {
            let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
            if snapshot == INVALID_HANDLE_VALUE {
                return Err(failed("cannot list the adapter's threads"));
            }
            let mut entry: THREADENTRY32 = std::mem::zeroed();
            entry.dwSize = std::mem::size_of::<THREADENTRY32>() as u32;
            let mut resumed = 0;
            let mut more = Thread32First(snapshot, &mut entry) != 0;
            while more {
                if entry.th32OwnerProcessID == pid {
                    let thread = OpenThread(THREAD_SUSPEND_RESUME, 0, entry.th32ThreadID);
                    if !thread.is_null() {
                        if ResumeThread(thread) != u32::MAX {
                            resumed += 1;
                        }
                        CloseHandle(thread);
                    }
                }
                more = Thread32Next(snapshot, &mut entry) != 0;
            }
            CloseHandle(snapshot);
            Ok(resumed)
        }
    }

    impl Tree {
        /// Places the suspended child in a new job that kills its members on
        /// close, then lets it run. Any failure is an error: an adapter that
        /// cannot be contained is not started.
        pub fn attach(child: &Child) -> Result<Self, String> {
            // SAFETY: Win32 calls on a handle this function owns and on the
            // live child's process handle; the job is closed on every error.
            unsafe {
                let job = CreateJobObjectW(std::ptr::null(), std::ptr::null());
                if job.is_null() {
                    return Err(failed("cannot create a Job Object for the adapter"));
                }
                let tree = Self { job };
                let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
                info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                let configured = SetInformationJobObject(
                    job,
                    JobObjectExtendedLimitInformation,
                    std::ptr::from_ref(&info).cast(),
                    std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
                );
                if configured == 0 {
                    return Err(failed("cannot configure the adapter's Job Object"));
                }
                if AssignProcessToJobObject(job, child.as_raw_handle() as HANDLE) == 0 {
                    return Err(failed("cannot place the adapter in its Job Object"));
                }
                match resume(child.id())? {
                    0 => Err(
                        "cannot resume the adapter after placing it in its Job Object".to_owned(),
                    ),
                    _ => Ok(tree),
                }
            }
        }

        pub fn kill(&self) {
            // SAFETY: `job` is a live job handle owned by this value.
            unsafe {
                TerminateJobObject(self.job, 1);
            }
        }
    }

    impl Drop for Tree {
        fn drop(&mut self) {
            // SAFETY: closing the handle this value owns, exactly once.
            unsafe {
                CloseHandle(self.job);
            }
        }
    }
}
/// Prepares a command to run as the root of a killable tree.
pub fn configure(command: &mut Command) {
    imp::configure(command);
}

/// The tree rooted at a started adapter.
pub struct ProcessTree(Arc<imp::Tree>);

/// Kills an adapter's tree from any thread, for example on Ctrl-C while a
/// request is outstanding. The adapter itself is part of its tree.
#[derive(Clone)]
pub struct Terminator(Arc<imp::Tree>);

impl Terminator {
    pub fn kill(&self) {
        self.0.kill();
    }
}

impl ProcessTree {
    /// Takes charge of a just-started adapter, or says why it cannot; the
    /// caller must then kill the child it could not contain.
    pub fn attach(child: &Child) -> Result<Self, String> {
        imp::Tree::attach(child).map(|tree| Self(Arc::new(tree)))
    }

    pub fn terminator(&self) -> Terminator {
        Terminator(Arc::clone(&self.0))
    }

    /// Kills the adapter and everything it started. Safe to call repeatedly.
    pub fn kill(&self, child: &mut Child) {
        self.0.kill();
        let _ = child.kill();
    }
}
