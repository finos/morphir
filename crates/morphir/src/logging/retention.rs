use fs2::FileExt as _;
use std::{
    ffi::OsStr,
    fs, io,
    path::{Path, PathBuf},
    time::{Duration, SystemTime},
};
use walkdir::WalkDir;

pub(super) const DEFAULT_LOG_RETENTION: Duration = Duration::from_secs(14 * 24 * 60 * 60);
pub(super) const DEFAULT_MAX_LOG_BYTES: u64 = 100 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
struct LogEntry {
    path: PathBuf,
    modified: SystemTime,
    size: u64,
    active: bool,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(super) struct RetentionResult {
    pub(super) removed_files: u64,
    pub(super) removed_bytes: u64,
}

pub(super) fn active_marker_path(log_path: &Path) -> PathBuf {
    log_path.with_extension("jsonl.active")
}

fn session_is_active(log_path: &Path) -> io::Result<bool> {
    let marker = active_marker_path(log_path);
    let marker_file = match fs::OpenOptions::new().read(true).write(true).open(&marker) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(false),
        Err(error) => return Err(error),
    };

    match marker_file.try_lock_exclusive() {
        Ok(()) => {
            fs2::FileExt::unlock(&marker_file)?;
            drop(marker_file);
            match fs::remove_file(marker) {
                Ok(()) => Ok(false),
                Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(false),
                Err(error) => Err(error),
            }
        }
        Err(error) if error.raw_os_error() == fs2::lock_contended_error().raw_os_error() => {
            Ok(true)
        }
        Err(error) => Err(error),
    }
}

fn is_managed_session_log(path: &Path) -> bool {
    let Some(directory) = path
        .parent()
        .and_then(Path::file_name)
        .and_then(OsStr::to_str)
    else {
        return false;
    };
    let Some(file_name) = path.file_name().and_then(OsStr::to_str) else {
        return false;
    };
    let Some(stem) = file_name.strip_suffix(".jsonl") else {
        return false;
    };
    let mut parts = stem.splitn(3, '-');
    let Some(timestamp) = parts.next() else {
        return false;
    };
    let Some(process_id) = parts.next() else {
        return false;
    };
    let Some(session_id) = parts.next() else {
        return false;
    };

    chrono::NaiveDate::parse_from_str(directory, "%Y-%m-%d").is_ok()
        && chrono::NaiveDateTime::parse_from_str(timestamp, "%Y%m%dT%H%M%S%.3fZ").is_ok()
        && process_id.parse::<u32>().is_ok()
        && !session_id.is_empty()
}

fn collect_log_entries(log_dir: &Path) -> io::Result<Vec<LogEntry>> {
    if !log_dir.exists() {
        return Ok(Vec::new());
    }

    let entries = WalkDir::new(log_dir)
        .min_depth(2)
        .max_depth(2)
        .follow_links(false)
        .into_iter()
        .map(|entry| {
            let entry = entry.map_err(io::Error::other)?;
            if !entry.file_type().is_file() || !is_managed_session_log(entry.path()) {
                return Ok(None);
            }

            let metadata = entry.metadata().map_err(io::Error::other)?;
            let path = entry.into_path();
            Ok(Some(LogEntry {
                modified: metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH),
                size: metadata.len(),
                active: session_is_active(&path)?,
                path,
            }))
        })
        .collect::<io::Result<Vec<_>>>()?;

    Ok(entries.into_iter().flatten().collect())
}

fn select_logs_for_removal(
    mut entries: Vec<LogEntry>,
    now: SystemTime,
    max_age: Duration,
    max_bytes: u64,
) -> Vec<PathBuf> {
    entries.sort_by(|left, right| {
        left.modified
            .cmp(&right.modified)
            .then_with(|| left.path.cmp(&right.path))
    });

    let mut remaining_bytes = entries.iter().map(|entry| entry.size).sum::<u64>();
    let mut selected = Vec::new();
    let mut removed = vec![false; entries.len()];

    for (index, entry) in entries.iter().enumerate() {
        let expired = now.duration_since(entry.modified).unwrap_or_default() >= max_age;
        if expired && !entry.active {
            remaining_bytes = remaining_bytes.saturating_sub(entry.size);
            selected.push(entry.path.clone());
            removed[index] = true;
        }
    }

    for (index, entry) in entries.iter().enumerate() {
        if remaining_bytes <= max_bytes {
            break;
        }
        if !removed[index] && !entry.active {
            remaining_bytes = remaining_bytes.saturating_sub(entry.size);
            selected.push(entry.path.clone());
        }
    }

    selected
}

pub(super) fn enforce_log_retention(
    log_dir: &Path,
    now: SystemTime,
    max_age: Duration,
    max_bytes: u64,
) -> io::Result<RetentionResult> {
    let entries = collect_log_entries(log_dir)?;
    let selected = select_logs_for_removal(entries, now, max_age, max_bytes);

    selected
        .into_iter()
        .try_fold(RetentionResult::default(), |mut result, path| {
            if session_is_active(&path)? {
                return Ok(result);
            }

            let size = fs::metadata(&path)
                .map(|metadata| metadata.len())
                .unwrap_or(0);
            match fs::remove_file(&path) {
                Ok(()) => {
                    result.removed_files += 1;
                    result.removed_bytes += size;
                    Ok(result)
                }
                Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(result),
                Err(error) => Err(error),
            }
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn removes_expired_and_oldest_completed_sessions() {
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(30 * 24 * 60 * 60);
        let entry = |name: &str, age_days: u64, size: u64, active: bool| LogEntry {
            path: PathBuf::from(name),
            modified: now - Duration::from_secs(age_days * 24 * 60 * 60),
            size,
            active,
        };
        let entries = vec![
            entry("expired.jsonl", 15, 10, false),
            entry("active.jsonl", 20, 70, true),
            entry("oldest.jsonl", 10, 50, false),
            entry("newest.jsonl", 1, 20, false),
        ];

        assert_eq!(
            select_logs_for_removal(entries, now, Duration::from_secs(14 * 24 * 60 * 60), 100,),
            vec![
                PathBuf::from("expired.jsonl"),
                PathBuf::from("oldest.jsonl")
            ]
        );
    }

    #[test]
    fn deletes_only_completed_managed_session_logs() {
        let temporary = tempfile::tempdir().unwrap();
        let daily = temporary.path().join("2026-08-29");
        fs::create_dir(&daily).unwrap();

        let completed = daily.join("20260829T140312.456Z-42-2a-a.jsonl");
        let active = daily.join("20260829T140313.456Z-43-2b-b.jsonl");
        let unknown = daily.join("notes.jsonl");
        fs::write(&completed, "completed").unwrap();
        fs::write(&active, "active").unwrap();
        fs::write(&unknown, "unknown").unwrap();

        let active_marker = active_marker_path(&active);
        let marker_file = fs::File::create(&active_marker).unwrap();
        fs2::FileExt::try_lock_exclusive(&marker_file).unwrap();

        let result =
            enforce_log_retention(temporary.path(), SystemTime::now(), Duration::MAX, 0).unwrap();

        assert_eq!(result.removed_files, 1);
        assert!(!completed.exists());
        assert!(active.exists());
        assert!(unknown.exists());
    }
}
