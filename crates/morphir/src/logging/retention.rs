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

#[derive(Debug, Clone, PartialEq, Eq)]
struct RemovalCandidate {
    entry: LogEntry,
    expired: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SessionState {
    Completed,
    Active,
    Unavailable,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(super) struct RetentionResult {
    pub(super) removed_files: u64,
    pub(super) removed_bytes: u64,
    pub(super) skipped_entries: u64,
}

pub(super) fn active_marker_path(log_path: &Path) -> PathBuf {
    log_path.with_extension("jsonl.active")
}

fn session_state(log_path: &Path) -> SessionState {
    let marker = active_marker_path(log_path);
    let marker_file = match fs::OpenOptions::new().read(true).write(true).open(&marker) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return SessionState::Completed,
        Err(_) => return SessionState::Unavailable,
    };

    match marker_file.try_lock_exclusive() {
        Ok(()) => {
            if fs2::FileExt::unlock(&marker_file).is_err() {
                return SessionState::Unavailable;
            }
            drop(marker_file);
            match fs::remove_file(marker) {
                Ok(()) => SessionState::Completed,
                Err(error) if error.kind() == io::ErrorKind::NotFound => SessionState::Completed,
                Err(_) => SessionState::Unavailable,
            }
        }
        Err(error) if error.raw_os_error() == fs2::lock_contended_error().raw_os_error() => {
            SessionState::Active
        }
        Err(_) => SessionState::Unavailable,
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
    let Some(process_id_text) = parts.next() else {
        return false;
    };
    let Some(session_id) = parts.next() else {
        return false;
    };
    let Some((session_process_id, session_timestamp_nanos)) = session_id.split_once('-') else {
        return false;
    };
    let Ok(process_id) = process_id_text.parse::<u32>() else {
        return false;
    };
    let lower_hex = |value: &str| {
        !value.is_empty()
            && value
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    };
    if !lower_hex(session_process_id)
        || !lower_hex(session_timestamp_nanos)
        || process_id_text != process_id.to_string()
        || session_process_id != format!("{process_id:x}")
    {
        return false;
    }
    let Ok(timestamp_nanos) = u64::from_str_radix(session_timestamp_nanos, 16) else {
        return false;
    };
    let Ok(timestamp_nanos) = i64::try_from(timestamp_nanos) else {
        return false;
    };
    if session_timestamp_nanos != format!("{timestamp_nanos:x}") {
        return false;
    }
    let session_time = chrono::DateTime::<chrono::Utc>::from_timestamp_nanos(timestamp_nanos);
    let session_timestamp = session_time.format("%Y%m%dT%H%M%S%.3fZ").to_string();
    let session_directory = session_time.format("%Y-%m-%d").to_string();

    is_managed_date_directory(path.parent().unwrap_or_else(|| Path::new("")))
        && chrono::NaiveDateTime::parse_from_str(timestamp, "%Y%m%dT%H%M%S%.3fZ").is_ok()
        && directory == session_directory
        && timestamp == session_timestamp
}

fn is_managed_date_directory(path: &Path) -> bool {
    let Some(directory) = path.file_name().and_then(OsStr::to_str) else {
        return false;
    };
    chrono::NaiveDate::parse_from_str(directory, "%Y-%m-%d")
        .is_ok_and(|date| directory == date.format("%Y-%m-%d").to_string())
}

fn collect_log_entries(log_dir: &Path) -> (Vec<LogEntry>, u64) {
    if !log_dir.exists() {
        return (Vec::new(), 0);
    }

    WalkDir::new(log_dir)
        .min_depth(2)
        .max_depth(2)
        .follow_links(false)
        .into_iter()
        .filter_entry(|entry| {
            entry.depth() != 1
                || (entry.file_type().is_dir() && is_managed_date_directory(entry.path()))
        })
        .fold((Vec::new(), 0), |(mut entries, mut skipped), entry| {
            let Ok(entry) = entry else {
                return (entries, skipped + 1);
            };
            if !entry.file_type().is_file() || !is_managed_session_log(entry.path()) {
                return (entries, skipped);
            }

            let Ok(metadata) = entry.metadata() else {
                return (entries, skipped + 1);
            };
            let Ok(modified) = metadata.modified() else {
                return (entries, skipped + 1);
            };
            let path = entry.into_path();
            let state = session_state(&path);
            if state == SessionState::Unavailable {
                skipped += 1;
            }
            entries.push(LogEntry {
                modified,
                size: metadata.len(),
                active: state != SessionState::Completed,
                path,
            });
            (entries, skipped)
        })
}

fn plan_log_retention(
    mut entries: Vec<LogEntry>,
    now: SystemTime,
    max_age: Duration,
) -> (u64, Vec<RemovalCandidate>) {
    entries.sort_by(|left, right| {
        left.modified
            .cmp(&right.modified)
            .then_with(|| left.path.cmp(&right.path))
    });

    let remaining_bytes = entries.iter().map(|entry| entry.size).sum::<u64>();
    let (expired, current): (Vec<_>, Vec<_>) = entries
        .into_iter()
        .filter(|entry| !entry.active)
        .partition(|entry| now.duration_since(entry.modified).unwrap_or_default() >= max_age);
    let candidates = expired
        .into_iter()
        .map(|entry| RemovalCandidate {
            entry,
            expired: true,
        })
        .chain(current.into_iter().map(|entry| RemovalCandidate {
            entry,
            expired: false,
        }))
        .collect();

    (remaining_bytes, candidates)
}

pub(super) fn enforce_log_retention(
    log_dir: &Path,
    now: SystemTime,
    max_age: Duration,
    max_bytes: u64,
) -> RetentionResult {
    let (entries, skipped_entries) = collect_log_entries(log_dir);
    let (remaining_bytes, candidates) = plan_log_retention(entries, now, max_age);

    remove_log_candidates(
        candidates,
        remaining_bytes,
        max_bytes,
        skipped_entries,
        |path| fs::remove_file(path),
    )
}

fn remove_log_candidates(
    candidates: Vec<RemovalCandidate>,
    mut remaining_bytes: u64,
    max_bytes: u64,
    skipped_entries: u64,
    mut remove: impl FnMut(&Path) -> io::Result<()>,
) -> RetentionResult {
    let mut result = RetentionResult {
        skipped_entries,
        ..RetentionResult::default()
    };

    for candidate in candidates {
        if !candidate.expired && remaining_bytes <= max_bytes {
            break;
        }
        match session_state(&candidate.entry.path) {
            SessionState::Active => continue,
            SessionState::Unavailable => {
                result.skipped_entries += 1;
                continue;
            }
            SessionState::Completed => {}
        }

        match remove(&candidate.entry.path) {
            Ok(()) => {
                result.removed_files += 1;
                result.removed_bytes += candidate.entry.size;
                remaining_bytes = remaining_bytes.saturating_sub(candidate.entry.size);
            }
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                remaining_bytes = remaining_bytes.saturating_sub(candidate.entry.size);
            }
            Err(_) => result.skipped_entries += 1,
        }
    }

    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn managed_log_path(directory: &Path, timestamp: &str, process_id: u32) -> PathBuf {
        let timestamp = chrono::DateTime::parse_from_rfc3339(timestamp)
            .unwrap()
            .to_utc();
        let timestamp_nanos = timestamp.timestamp_nanos_opt().unwrap() as u64;
        directory.join(format!(
            "{}-{process_id}-{process_id:x}-{timestamp_nanos:x}.jsonl",
            timestamp.format("%Y%m%dT%H%M%S%.3fZ")
        ))
    }

    #[test]
    fn recognizes_only_exact_generated_session_names() {
        let timestamp = chrono::DateTime::parse_from_rfc3339("2026-08-29T14:03:12.456Z")
            .unwrap()
            .to_utc();
        let timestamp_nanos = timestamp.timestamp_nanos_opt().unwrap() as u64;
        let directory = PathBuf::from("2026-08-29");
        let valid = directory.join(format!(
            "20260829T140312.456Z-42-2a-{timestamp_nanos:x}.jsonl"
        ));

        assert!(is_managed_session_log(&valid));
        assert!(!is_managed_session_log(
            &directory.join("20260829T140312.456Z-42-backup.jsonl")
        ));
        assert!(!is_managed_session_log(&directory.join(format!(
            "20260829T140312.456Z-42-2b-{timestamp_nanos:x}.jsonl"
        ))));
        assert!(!is_managed_session_log(
            &directory.join("20260829T140312.456Z-42-2a-1.jsonl")
        ));
        assert!(!is_managed_session_log(&PathBuf::from("2026-08-30").join(
            format!("20260829T140312.456Z-42-2a-{timestamp_nanos:x}.jsonl")
        )));
    }

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

        let (remaining_bytes, candidates) =
            plan_log_retention(entries, now, Duration::from_secs(14 * 24 * 60 * 60));
        let mut removed = Vec::new();
        let result = remove_log_candidates(candidates, remaining_bytes, 100, 0, |path| {
            removed.push(path.to_path_buf());
            Ok(())
        });

        assert_eq!(
            removed,
            vec![
                PathBuf::from("expired.jsonl"),
                PathBuf::from("oldest.jsonl")
            ]
        );
        assert_eq!(result.removed_files, 2);
        assert_eq!(result.removed_bytes, 60);
    }

    #[test]
    fn deletes_only_completed_managed_session_logs() {
        let temporary = tempfile::tempdir().unwrap();
        let daily = temporary.path().join("2026-08-29");
        fs::create_dir(&daily).unwrap();

        let completed = managed_log_path(&daily, "2026-08-29T14:03:12.456Z", 42);
        let active = managed_log_path(&daily, "2026-08-29T14:03:13.456Z", 43);
        let unknown = daily.join("notes.jsonl");
        fs::write(&completed, "completed").unwrap();
        fs::write(&active, "active").unwrap();
        fs::write(&unknown, "unknown").unwrap();

        let active_marker = active_marker_path(&active);
        let marker_file = fs::File::create(&active_marker).unwrap();
        fs2::FileExt::try_lock_exclusive(&marker_file).unwrap();

        let result = enforce_log_retention(temporary.path(), SystemTime::now(), Duration::MAX, 0);

        assert_eq!(result.removed_files, 1);
        assert!(!completed.exists());
        assert!(active.exists());
        assert!(unknown.exists());
    }

    #[test]
    fn protects_unreadable_markers_without_stopping_other_cleanup() {
        let temporary = tempfile::tempdir().unwrap();
        let daily = temporary.path().join("2026-08-29");
        fs::create_dir(&daily).unwrap();

        let protected = managed_log_path(&daily, "2026-08-29T14:03:12.456Z", 42);
        let completed = managed_log_path(&daily, "2026-08-29T14:03:13.456Z", 43);
        fs::write(&protected, "protected").unwrap();
        fs::write(&completed, "completed").unwrap();
        fs::create_dir(active_marker_path(&protected)).unwrap();

        let result = enforce_log_retention(temporary.path(), SystemTime::now(), Duration::MAX, 0);

        assert_eq!(result.removed_files, 1);
        assert_eq!(result.skipped_entries, 1);
        assert!(protected.exists());
        assert!(!completed.exists());
    }

    #[test]
    fn continues_after_an_individual_deletion_failure() {
        let now = SystemTime::UNIX_EPOCH + Duration::from_secs(30 * 24 * 60 * 60);
        let blocked = LogEntry {
            path: PathBuf::from("blocked.jsonl"),
            modified: now - Duration::from_secs(15 * 24 * 60 * 60),
            size: 30,
            active: false,
        };
        let removable = LogEntry {
            path: PathBuf::from("removable.jsonl"),
            modified: now - Duration::from_secs(24 * 60 * 60),
            size: 90,
            active: false,
        };
        let (remaining_bytes, candidates) = plan_log_retention(
            vec![blocked.clone(), removable.clone()],
            now,
            Duration::from_secs(14 * 24 * 60 * 60),
        );
        let mut attempted = Vec::new();
        let result = remove_log_candidates(candidates, remaining_bytes, 100, 0, |path| {
            attempted.push(path.to_path_buf());
            if path == blocked.path {
                Err(io::Error::new(io::ErrorKind::PermissionDenied, "blocked"))
            } else {
                Ok(())
            }
        });

        assert_eq!(result.removed_files, 1);
        assert_eq!(result.removed_bytes, 90);
        assert_eq!(result.skipped_entries, 1);
        assert_eq!(attempted, vec![blocked.path, removable.path]);
    }

    #[cfg(unix)]
    #[test]
    fn ignores_unreadable_unknown_directories_and_cleans_managed_logs() {
        use std::os::unix::fs::PermissionsExt as _;

        let temporary = tempfile::tempdir().unwrap();
        let blocked = temporary.path().join("blocked");
        let daily = temporary.path().join("2026-08-29");
        fs::create_dir(&blocked).unwrap();
        fs::create_dir(&daily).unwrap();
        fs::set_permissions(&blocked, fs::Permissions::from_mode(0o000)).unwrap();
        let completed = managed_log_path(&daily, "2026-08-29T14:03:13.456Z", 43);
        fs::write(&completed, "completed").unwrap();

        let result = enforce_log_retention(temporary.path(), SystemTime::now(), Duration::MAX, 0);
        fs::set_permissions(&blocked, fs::Permissions::from_mode(0o700)).unwrap();

        assert_eq!(result.removed_files, 1);
        assert_eq!(result.skipped_entries, 0);
        assert!(!completed.exists());
    }

    #[cfg(unix)]
    #[test]
    fn skips_unreadable_managed_date_directories_and_continues_cleanup() {
        use std::os::unix::fs::PermissionsExt as _;

        let temporary = tempfile::tempdir().unwrap();
        let blocked = temporary.path().join("2026-08-28");
        let daily = temporary.path().join("2026-08-29");
        fs::create_dir(&blocked).unwrap();
        fs::create_dir(&daily).unwrap();
        fs::set_permissions(&blocked, fs::Permissions::from_mode(0o000)).unwrap();
        let completed = managed_log_path(&daily, "2026-08-29T14:03:13.456Z", 43);
        fs::write(&completed, "completed").unwrap();

        let result = enforce_log_retention(temporary.path(), SystemTime::now(), Duration::MAX, 0);
        fs::set_permissions(&blocked, fs::Permissions::from_mode(0o700)).unwrap();

        assert_eq!(result.removed_files, 1);
        assert_eq!(result.skipped_entries, 1);
        assert!(!completed.exists());
    }
}
