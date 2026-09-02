use super::{DesktopLifecycle, lifecycle_from_event};
use std::{
    collections::BTreeMap,
    fs,
    io::{self, Read, Seek, SeekFrom},
    path::{Path, PathBuf},
};

const MAX_DISCOVERY_ENTRIES: usize = 50_000;
const MAX_POLL_BYTES: usize = 1024 * 1024;
const MAX_FILE_BYTES: usize = 256 * 1024;
const MAX_LINE_BYTES: usize = 64 * 1024;

/// Snapshot before spawning so fast children cannot write readiness before the
/// starting offsets are captured. Existing single-instance sessions can append
/// the new launch ID to an older file, so those files must also remain visible.
pub(super) struct ReadinessLogs {
    root: PathBuf,
    cursors: BTreeMap<PathBuf, LogCursor>,
    resume_after: Option<PathBuf>,
    observed: Option<DesktopLifecycle>,
    discovery_limit: usize,
    #[cfg(test)]
    bytes_read: usize,
}

impl ReadinessLogs {
    pub(super) fn snapshot(root: &Path) -> io::Result<Self> {
        Self::snapshot_with_limit(root, MAX_DISCOVERY_ENTRIES)
    }

    pub(super) fn snapshot_with_limit(root: &Path, discovery_limit: usize) -> io::Result<Self> {
        Ok(Self {
            root: root.to_path_buf(),
            cursors: log_sizes(root, discovery_limit)?
                .into_iter()
                .map(|(path, offset)| {
                    (
                        path,
                        LogCursor {
                            offset,
                            ..LogCursor::default()
                        },
                    )
                })
                .collect(),
            resume_after: None,
            observed: None,
            discovery_limit,
            #[cfg(test)]
            bytes_read: 0,
        })
    }

    pub(super) fn poll(&mut self, launch_id: &str) -> io::Result<Option<DesktopLifecycle>> {
        let files = log_sizes(&self.root, self.discovery_limit)?;
        self.cursors.retain(|path, _| files.contains_key(path));
        let files = files.into_iter().collect::<Vec<_>>();
        let start = self
            .resume_after
            .as_ref()
            .map_or(0, |last| files.partition_point(|(path, _)| path <= last));
        let mut remaining = MAX_POLL_BYTES;
        let mut caught_up = true;
        for (path, size) in files[start..].iter().chain(&files[..start]) {
            if remaining == 0 {
                caught_up = false;
                break;
            }
            self.resume_after = Some(path.clone());
            let cursor = self.cursors.entry(path.clone()).or_default();
            if *size < cursor.offset {
                *cursor = LogCursor::default();
            }
            if *size == cursor.offset {
                continue;
            }
            let Ok(bytes) = cursor.read_appended(path, *size, remaining.min(MAX_FILE_BYTES)) else {
                continue;
            };
            remaining -= bytes.len();
            #[cfg(test)]
            {
                self.bytes_read += bytes.len();
            }
            caught_up &= cursor.offset == *size;
            for byte in bytes {
                if let Some(event) = cursor.push_byte(byte, launch_id)
                    && (event == DesktopLifecycle::Ready
                        || self.observed != Some(DesktopLifecycle::Ready))
                {
                    self.observed = Some(event);
                }
            }
        }
        // Readiness wins even if a fast process exits in the same poll. Do not
        // report a terminal event while another file still has unread records.
        Ok(
            if caught_up || self.observed == Some(DesktopLifecycle::Ready) {
                self.observed.clone()
            } else {
                None
            },
        )
    }
}

#[derive(Default)]
struct LogCursor {
    offset: u64,
    line: Vec<u8>,
    discarding: bool,
}

impl LogCursor {
    fn read_appended(&mut self, path: &Path, size: u64, limit: usize) -> io::Result<Vec<u8>> {
        let mut file = fs::File::open(path)?;
        file.seek(SeekFrom::Start(self.offset))?;
        let available = size.saturating_sub(self.offset).min(limit as u64);
        let mut bytes = Vec::with_capacity(available as usize);
        file.take(available).read_to_end(&mut bytes)?;
        self.offset += bytes.len() as u64;
        Ok(bytes)
    }

    fn push_byte(&mut self, byte: u8, launch_id: &str) -> Option<DesktopLifecycle> {
        if byte == b'\n' {
            let event = (!self.discarding)
                .then(|| serde_json::from_slice(&self.line).ok())
                .flatten()
                .and_then(|event| lifecycle_from_event(&event, launch_id));
            self.line.clear();
            self.discarding = false;
            return event;
        }
        if !self.discarding {
            if self.line.len() == MAX_LINE_BYTES {
                self.line.clear();
                self.discarding = true;
            } else {
                self.line.push(byte);
            }
        }
        None
    }
}

fn log_sizes(root: &Path, entry_limit: usize) -> io::Result<BTreeMap<PathBuf, u64>> {
    let mut files = BTreeMap::new();
    // Desktop writes root/YYYY-MM-DD/session.jsonl. Flat roots also support
    // configured log writers. Never traverse crash trees or directory links.
    for (index, entry) in walkdir::WalkDir::new(root)
        .max_depth(2)
        .into_iter()
        .enumerate()
    {
        if index == entry_limit {
            return Err(io::Error::other(format!(
                "Desktop log discovery exceeded {entry_limit} entries"
            )));
        }
        let Ok(entry) = entry else { continue };
        if entry.file_type().is_file()
            && entry
                .path()
                .extension()
                .is_some_and(|extension| extension == "jsonl")
            && let Ok(metadata) = entry.metadata()
        {
            files.insert(entry.into_path(), metadata.len());
        }
    }
    Ok(files)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{fs, io::Write};

    fn event(name: &str) -> String {
        format!("{{\"fields\":{{\"event_name\":\"{name}\",\"launch_id\":\"launch-expected\"}}}}\n")
    }

    fn append(path: &std::path::Path, bytes: &[u8]) {
        fs::OpenOptions::new()
            .append(true)
            .open(path)
            .unwrap()
            .write_all(bytes)
            .unwrap();
    }

    #[test]
    fn readiness_skips_history_and_reads_each_append_only_once() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("existing.jsonl");
        fs::File::create(&path)
            .unwrap()
            .set_len(64 * 1024 * 1024)
            .unwrap();
        let mut reader = ReadinessLogs::snapshot(root.path()).unwrap();
        assert_eq!(reader.poll("launch-expected").unwrap(), None);
        assert_eq!(reader.bytes_read, 0);
        let ready = event("desktop.ready");
        append(&path, ready.as_bytes());
        assert_eq!(
            reader.poll("launch-expected").unwrap(),
            Some(DesktopLifecycle::Ready)
        );
        assert_eq!(reader.bytes_read, ready.len());
        reader.poll("launch-expected").unwrap();
        assert_eq!(reader.bytes_read, ready.len());
    }

    #[test]
    fn readiness_finds_fast_new_sessions_and_prefers_ready_over_exit() {
        let root = tempfile::tempdir().unwrap();
        let mut reader = ReadinessLogs::snapshot(root.path()).unwrap();
        fs::create_dir(root.path().join("2026-09-02")).unwrap();
        fs::write(
            root.path().join("2026-09-02/new.jsonl"),
            event("desktop.ready") + &event("desktop.exit"),
        )
        .unwrap();
        assert_eq!(
            reader.poll("launch-expected").unwrap(),
            Some(DesktopLifecycle::Ready)
        );
    }

    #[test]
    fn readiness_keeps_partial_lines_until_the_next_poll() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("partial.jsonl");
        let mut reader = ReadinessLogs::snapshot(root.path()).unwrap();
        let ready = event("desktop.ready");
        fs::write(&path, &ready.as_bytes()[..20]).unwrap();
        assert_eq!(reader.poll("launch-expected").unwrap(), None);
        append(&path, &ready.as_bytes()[20..]);
        assert_eq!(
            reader.poll("launch-expected").unwrap(),
            Some(DesktopLifecycle::Ready)
        );
    }

    #[test]
    fn readiness_recovers_from_truncation_and_oversized_records() {
        let root = tempfile::tempdir().unwrap();
        let path = root.path().join("session.jsonl");
        fs::write(&path, vec![b'x'; MAX_POLL_BYTES * 2]).unwrap();
        let mut reader = ReadinessLogs::snapshot(root.path()).unwrap();
        let mut contents = vec![b'x'; MAX_LINE_BYTES + 1];
        contents.push(b'\n');
        contents.extend_from_slice(event("desktop.ready").as_bytes());
        fs::write(&path, contents).unwrap();
        assert_eq!(
            reader.poll("launch-expected").unwrap(),
            Some(DesktopLifecycle::Ready)
        );
    }

    #[test]
    fn readiness_bounds_each_poll_without_starving_later_files() {
        let root = tempfile::tempdir().unwrap();
        let mut reader = ReadinessLogs::snapshot(root.path()).unwrap();
        for index in 0..8 {
            fs::write(
                root.path().join(format!("noise-{index}.jsonl")),
                vec![b'x'; MAX_POLL_BYTES * 2],
            )
            .unwrap();
        }
        fs::write(root.path().join("ready.jsonl"), event("desktop.ready")).unwrap();
        for _ in 0..10 {
            let before = reader.bytes_read;
            let observed = reader.poll("launch-expected").unwrap();
            assert!(reader.bytes_read - before <= MAX_POLL_BYTES);
            if observed == Some(DesktopLifecycle::Ready) {
                return;
            }
        }
        panic!("busy files starved the ready event");
    }
}
