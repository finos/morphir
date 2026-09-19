//! The adapter's process tree. An adapter may start processes of its own, so
//! terminating only the adapter could leave its children running, holding the
//! pipes open. On Unix the adapter leads a new process group and the whole
//! group is killed; on Windows it is placed in a Job Object that is terminated,
//! and that kills its members when its last handle closes. The adapter never
//! opens a console window on Windows.

use std::process::{Child, Command};

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
        pub fn attach(child: &Child) -> Self {
            Self {
                group: Pid::from_child(child),
            }
        }

        pub fn kill(&self) {
            // The group may already be gone; that is the goal, not an error.
            let _ = kill_process_group(self.group, Signal::KILL);
        }
    }
}

#[cfg(windows)]
mod imp {
    use std::os::windows::io::AsRawHandle as _;
    use std::process::{Child, Command};

    use windows_sys::Win32::Foundation::{CloseHandle, HANDLE};
    use windows_sys::Win32::System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
        SetInformationJobObject, TerminateJobObject,
    };

    /// `CREATE_NO_WINDOW`: a console child gets no console window.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;

    pub fn configure(command: &mut Command) {
        use std::os::windows::process::CommandExt as _;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    pub struct Tree {
        job: HANDLE,
    }

    // The job handle is only used to terminate and close the job, which the
    // system allows from any thread.
    unsafe impl Send for Tree {}

    impl Tree {
        /// Places the child in a new job that kills its members on close. A
        /// process the child starts before this runs is outside the job; the
        /// adapter has done nothing but start by then.
        pub fn attach(child: &Child) -> Self {
            // SAFETY: plain Win32 calls on a handle this function owns and on
            // the live child's process handle. A failure leaves `job` null or
            // unassigned, and `kill` then falls back to killing the child.
            unsafe {
                let job = CreateJobObjectW(std::ptr::null(), std::ptr::null());
                if job.is_null() {
                    return Self { job };
                }
                let mut info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
                info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                SetInformationJobObject(
                    job,
                    JobObjectExtendedLimitInformation,
                    std::ptr::from_ref(&info).cast(),
                    std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
                );
                AssignProcessToJobObject(job, child.as_raw_handle() as HANDLE);
                Self { job }
            }
        }

        pub fn kill(&self) {
            if !self.job.is_null() {
                // SAFETY: `job` is a live job handle owned by this value.
                unsafe {
                    TerminateJobObject(self.job, 1);
                }
            }
        }
    }

    impl Drop for Tree {
        fn drop(&mut self) {
            if !self.job.is_null() {
                // SAFETY: closing the handle this value owns, exactly once.
                unsafe {
                    CloseHandle(self.job);
                }
            }
        }
    }
}

/// Prepares a command to run as the root of a killable tree.
pub fn configure(command: &mut Command) {
    imp::configure(command);
}

/// The tree rooted at a started adapter.
pub struct ProcessTree(imp::Tree);

impl ProcessTree {
    pub fn attach(child: &Child) -> Self {
        Self(imp::Tree::attach(child))
    }

    /// Kills the adapter and everything it started. Safe to call repeatedly.
    pub fn kill(&self, child: &mut Child) {
        self.0.kill();
        let _ = child.kill();
    }
}
