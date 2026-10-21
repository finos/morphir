//! Two explicit owned endpoints. No arbitrary descriptor map or process identity.
use std::{
    io,
    os::{
        fd::{AsRawFd, FromRawFd, OwnedFd, RawFd},
        unix::{net::UnixStream, process::CommandExt},
    },
    process::Command,
};

const F_GETFD: i32 = 1;
const F_SETFD: i32 = 2;
const F_DUPFD_CLOEXEC: i32 = 67;
const FD_CLOEXEC: i32 = 1;
unsafe extern "C" {
    fn fcntl(fd: i32, command: i32, ...) -> i32;
}

pub(crate) struct OwnedConsumerChildEnds {
    outer: OwnedFd,
    helper: OwnedFd,
}
impl OwnedConsumerChildEnds {
    pub(crate) fn new(outer: UnixStream, helper: UnixStream) -> io::Result<Self> {
        fn normalize(socket: UnixStream) -> io::Result<OwnedFd> {
            let original: OwnedFd = socket.into();
            if original.as_raw_fd() >= 3 {
                return Ok(original);
            }
            // SAFETY: original is live and the SDK operation creates a NEW
            // CLOEXEC owner. It cannot alias a live std/private descriptor.
            let raw = unsafe { fcntl(original.as_raw_fd(), F_DUPFD_CLOEXEC, 3) };
            if raw < 0 {
                return Err(io::Error::last_os_error());
            }
            Ok(unsafe { OwnedFd::from_raw_fd(raw) })
        }
        Ok(Self {
            outer: normalize(outer)?,
            helper: normalize(helper)?,
        })
    }
    pub(crate) fn descriptors(&self) -> [RawFd; 2] {
        [self.outer.as_raw_fd(), self.helper.as_raw_fd()]
    }
    #[cfg(test)]
    pub(crate) fn test_handle(&self, helper: bool) -> std::os::fd::BorrowedFd<'_> {
        use std::os::fd::AsFd as _;
        if helper {
            self.helper.as_fd()
        } else {
            self.outer.as_fd()
        }
    }
    fn inheritance(descriptors: [RawFd; 2]) -> impl FnMut() -> io::Result<()> + Send + Sync {
        move || {
            for fd in descriptors {
                // SAFETY: these EXACT owned FDs stay live through spawn. Only
                // async-signal-safe fcntl/errno paths execute after fork. No remap,
                // allocation, formatting, mutex or destructor runs in this callback.
                let flags = unsafe { fcntl(fd, F_GETFD) };
                if flags < 0 || unsafe { fcntl(fd, F_SETFD, flags & !FD_CLOEXEC) } < 0 {
                    return Err(io::Error::last_os_error());
                }
            }
            Ok(())
        }
    }
    pub(crate) fn callback_storage() -> Option<usize> {
        // Pinned Rust1.98 std CommandExt boxes this exact callback and pushes
        // one entry into its initially empty pre_exec Vec. alloc::raw_vec's
        // minimum capacity is four for a16-byte boxed trait object. No other
        // pre_exec is installed here (process_group uses its dedicated field).
        // This is source-qualified heap storage, not allocator/RSS accounting.
        let callback = Self::inheritance([0, 0]); // never executed, no authority
        let slot = std::mem::size_of::<Box<dyn FnMut() -> io::Result<()> + Send + Sync>>();
        let capacity = if slot == 1 {
            8
        } else if slot <= 1024 {
            4
        } else {
            1
        };
        slot.checked_mul(capacity)?
            .checked_add(std::mem::size_of_val(&callback))
    }
}
pub(super) enum ChildHandles {
    Ordinary,
    Consumer(OwnedConsumerChildEnds),
}
impl ChildHandles {
    pub(super) fn configure(&self, command: &mut Command) {
        if let Self::Consumer(ends) = self {
            // SAFETY: inherit is restricted to the checked fcntl operations
            // above. OneShot's SAME local ChildHandles keeps the actual owners
            // alive through spawn; the callback captures only their numbers.
            unsafe {
                command.pre_exec(OwnedConsumerChildEnds::inheritance(ends.descriptors()));
            }
        }
    }
}
