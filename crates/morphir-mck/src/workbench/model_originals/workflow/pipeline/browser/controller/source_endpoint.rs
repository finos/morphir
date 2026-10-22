//! Fixed CDP endpoint DATA from the held profile. No loop renews the source end.
use super::*;
const PREFIX: &str = "ws://127.0.0.1:";

pub(super) fn read(
    target: &AcquiredTarget,
    scratch: &mut [u8],
    endpoint: &mut String,
    end: Instant,
) -> Result<bool, ControllerFault> {
    before(end)?;
    let fd = match rustix::fs::openat(
        &target.profile_dir,
        "DevToolsActivePort",
        rustix::fs::OFlags::RDONLY
            | rustix::fs::OFlags::NOFOLLOW
            | rustix::fs::OFlags::NONBLOCK
            | rustix::fs::OFlags::CLOEXEC,
        rustix::fs::Mode::empty(),
    ) {
        Ok(fd) => fd,
        Err(rustix::io::Errno::NOENT) => return Ok(false),
        Err(_) => return Err(ControllerFault::Acquisition),
    };
    let mut file = File::from(fd);
    before(end)?;
    let metadata = file.metadata().map_err(|_| ControllerFault::Acquisition)?;
    if !metadata.is_file() || metadata.len() > scratch.len() as u64 {
        return Err(ControllerFault::Shape);
    }
    let mut count = 0;
    loop {
        if count == scratch.len() {
            return Err(ControllerFault::Shape);
        }
        before(end)?;
        let read = file
            .read(&mut scratch[count..])
            .map_err(|_| ControllerFault::Acquisition)?;
        if read == 0 {
            break;
        }
        count += read;
    }
    decode(&scratch[..count], endpoint, end)
}
fn before(end: Instant) -> Result<(), ControllerFault> {
    if Instant::now() >= end {
        Err(ControllerFault::End)
    } else {
        Ok(())
    }
}
fn decode(raw: &[u8], endpoint: &mut String, end: Instant) -> Result<bool, ControllerFault> {
    let text = std::str::from_utf8(raw).map_err(|_| ControllerFault::Shape)?;
    let mut lines = text.lines();
    let Some(port) = lines.next() else {
        return Ok(false);
    };
    let Some(path) = lines.next() else {
        return Ok(false);
    };
    if port.is_empty()
        || port.len() > 5
        || port.starts_with('0')
        || !port.bytes().all(|b| b.is_ascii_digit())
        || port.parse::<u16>().ok().is_none_or(|value| value == 0)
        || !path.starts_with("/devtools/browser/")
        || lines.next().is_some()
    {
        return Err(ControllerFault::Shape);
    }
    let id = &path[18..];
    if id.len() < 36 {
        return Ok(false);
    }
    if id.len() != 36
        || !id.bytes().enumerate().all(|(at, byte)| {
            if matches!(at, 8 | 13 | 18 | 23) {
                byte == b'-'
            } else {
                byte.is_ascii_hexdigit()
            }
        })
    {
        return Err(ControllerFault::Shape);
    }
    let length = PREFIX
        .len()
        .checked_add(port.len())
        .and_then(|n| n.checked_add(path.len()))
        .ok_or(ControllerFault::Shape)?;
    if endpoint.capacity() < length {
        return Err(ControllerFault::Output);
    }
    before(end)?;
    endpoint.clear();
    for part in [PREFIX, port, path] {
        before(end)?;
        endpoint.push_str(part);
    }
    Ok(true)
}
