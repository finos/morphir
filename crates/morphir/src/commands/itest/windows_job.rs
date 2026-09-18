//! Own the entire CLI process tree, including workers outliving the CLI.
use anyhow::{Context, Result, bail};
use std::{
    io,
    mem::{size_of, zeroed},
    os::windows::{
        io::{AsRawHandle, FromRawHandle, OwnedHandle},
        process::CommandExt,
    },
    process::{Child, Command},
    ptr::null,
};
use windows_sys::Win32::{
    Foundation::INVALID_HANDLE_VALUE,
    System::{
        Diagnostics::ToolHelp::{
            CreateToolhelp32Snapshot, TH32CS_SNAPTHREAD, THREADENTRY32, Thread32First, Thread32Next,
        },
        JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
            SetInformationJobObject, TerminateJobObject,
        },
        Threading::{CREATE_SUSPENDED, OpenThread, ResumeThread, THREAD_SUSPEND_RESUME},
    },
};

pub(super) struct Job(OwnedHandle);

impl Job {
    pub(super) fn spawn(command: &mut Command) -> Result<(Self, Child)> {
        // SAFETY: null attributes/name request an unnamed, non-inheritable job.
        let raw = unsafe { CreateJobObjectW(null(), null()) };
        if raw.is_null() {
            return Err(io::Error::last_os_error()).context("create CLI job");
        }
        // SAFETY: CreateJobObjectW returned a new owned handle, checked above.
        let job = Self(unsafe { OwnedHandle::from_raw_handle(raw) });
        // SAFETY: zero is a valid initial state for this Win32 information struct.
        let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { zeroed() };
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        // SAFETY: the owned handle and correctly sized information buffer are valid.
        if unsafe {
            SetInformationJobObject(
                job.0.as_raw_handle(),
                JobObjectExtendedLimitInformation,
                (&limits as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
                size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )
        } == 0
        {
            return Err(io::Error::last_os_error()).context("configure CLI job cleanup");
        }
        // Suspension closes the race where a new CLI spawns a worker before
        // assignment to the job. Resume only after ownership is established.
        command.creation_flags(CREATE_SUSPENDED);
        let mut child = command.spawn().context("start suspended CLI")?;
        let attached = job.attach_and_resume(&child);
        if let Err(error) = attached {
            let _ = child.kill();
            let _ = child.wait();
            return Err(error);
        }
        Ok((job, child))
    }

    fn attach_and_resume(&self, child: &Child) -> Result<()> {
        // SAFETY: both process and job handles remain owned throughout this call.
        if unsafe { AssignProcessToJobObject(self.0.as_raw_handle(), child.as_raw_handle()) } == 0 {
            return Err(io::Error::last_os_error()).context("assign CLI to cleanup job");
        }
        // std's main_thread_handle is unstable. Find the suspended process's
        // initial thread through the stable ToolHelp API instead.
        // SAFETY: requesting a read-only system thread snapshot takes no pointers.
        let snapshot = unsafe { CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0) };
        if snapshot == INVALID_HANDLE_VALUE {
            return Err(io::Error::last_os_error()).context("snapshot CLI thread");
        }
        // SAFETY: the snapshot is a new valid owned handle.
        let snapshot = unsafe { OwnedHandle::from_raw_handle(snapshot) };
        // SAFETY: zero initialization is valid; dwSize is set before the API call.
        let mut entry: THREADENTRY32 = unsafe { zeroed() };
        entry.dwSize = size_of::<THREADENTRY32>() as u32;
        // SAFETY: snapshot and output buffer are valid for enumeration.
        let mut present = unsafe { Thread32First(snapshot.as_raw_handle(), &mut entry) };
        while present != 0 {
            if entry.th32OwnerProcessID == child.id() {
                // SAFETY: use the thread ID supplied by ToolHelp, requesting only resume rights.
                let thread = unsafe { OpenThread(THREAD_SUSPEND_RESUME, 0, entry.th32ThreadID) };
                if thread.is_null() {
                    return Err(io::Error::last_os_error()).context("open suspended CLI thread");
                }
                // SAFETY: OpenThread returned a new valid owned handle.
                let thread = unsafe { OwnedHandle::from_raw_handle(thread) };
                // SAFETY: this is the initial thread of our suspended CLI process.
                if unsafe { ResumeThread(thread.as_raw_handle()) } == u32::MAX {
                    return Err(io::Error::last_os_error()).context("resume CLI thread");
                }
                return Ok(());
            }
            // SAFETY: same owned snapshot and output buffer as above.
            present = unsafe { Thread32Next(snapshot.as_raw_handle(), &mut entry) };
        }
        bail!("could not locate the suspended CLI thread")
    }

    pub(super) fn terminate(&self) -> Result<()> {
        // SAFETY: the job handle remains owned and all assigned children belong to this run.
        if unsafe { TerminateJobObject(self.0.as_raw_handle(), 1) } == 0 {
            return Err(io::Error::last_os_error()).context("terminate CLI job");
        }
        Ok(())
    }
}
