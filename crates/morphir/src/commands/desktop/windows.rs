use miette::{IntoDiagnostic, WrapErr, miette};
use std::{
    ffi::OsString,
    io,
    os::windows::ffi::{OsStrExt, OsStringExt},
    path::{Path, PathBuf},
};
use windows_sys::Win32::Storage::FileSystem::GetShortPathNameW;

// Chromium's executable-path lookup still uses a MAX_PATH buffer, even when
// longPathAware enables long paths for the application's own filesystem I/O.
const ELECTRON_EXECUTABLE_PATH_LIMIT: usize = 260;

pub(super) fn executable_path(path: &Path) -> miette::Result<PathBuf> {
    let candidate = bounded_executable_path(path, existing_short_path)?;
    if candidate != path {
        let resolved = candidate
            .canonicalize()
            .into_diagnostic()
            .wrap_err("Could not verify the Desktop short executable path")?;
        if resolved != path.canonicalize().into_diagnostic()? {
            return Err(miette!(
                "Desktop short executable path does not resolve to the verified installation"
            ));
        }
    }
    Ok(candidate)
}

fn bounded_executable_path(
    path: &Path,
    short_path: impl FnOnce(&Path) -> io::Result<PathBuf>,
) -> miette::Result<PathBuf> {
    let fits =
        |path: &Path| path.as_os_str().encode_wide().count() < ELECTRON_EXECUTABLE_PATH_LIMIT;
    if fits(path) {
        return Ok(path.to_path_buf());
    }
    if let Ok(candidate) = short_path(path)
        && fits(&candidate)
    {
        return Ok(candidate);
    }
    Err(miette!(
        "The installed Desktop executable path exceeds Electron's Windows limit of 259 UTF-16 code units and no usable existing short filename is available. Set MORPHIR_HOME to a shorter directory and reinstall Desktop there. No Windows settings were changed."
    ))
}

fn existing_short_path(path: &Path) -> io::Result<PathBuf> {
    let input: Vec<u16> = path.as_os_str().encode_wide().chain(Some(0)).collect();
    // Windows extended-length paths are bounded by 32,767 UTF-16 code units.
    let mut output = vec![0_u16; 32_768];
    // SAFETY: input is NUL-terminated and both buffers remain valid for the call.
    let length =
        unsafe { GetShortPathNameW(input.as_ptr(), output.as_mut_ptr(), output.len() as u32) };
    if length == 0 {
        return Err(io::Error::last_os_error());
    }
    if length as usize >= output.len() {
        return Err(io::Error::other(
            "Windows short executable path exceeds the supported length",
        ));
    }
    Ok(PathBuf::from(OsString::from_wide(
        &output[..length as usize],
    )))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::windows::ffi::OsStrExt;

    #[test]
    fn deep_executable_uses_an_existing_short_name_or_reports_the_platform_limit() {
        let root = tempfile::tempdir().unwrap();
        let directory = root.path().join("a-long-package-directory-name".repeat(6));
        std::fs::create_dir(&directory).unwrap();
        let directory = directory.join("another-long-package-directory-name".repeat(3));
        std::fs::create_dir(&directory).unwrap();
        let original = directory.join("morphir-desktop.exe");
        std::fs::write(&original, b"fixture executable").unwrap();
        let original = original.canonicalize().unwrap();
        assert!(original.as_os_str().encode_wide().count() >= 260);
        match executable_path(&original) {
            Ok(path) => {
                assert!(path.as_os_str().encode_wide().count() < 260);
                assert_eq!(path.canonicalize().unwrap(), original);
            }
            Err(error) => {
                let message = error.to_string();
                assert!(message.contains("MORPHIR_HOME"), "{message}");
                assert!(message.contains("short"), "{message}");
            }
        }
    }

    #[test]
    fn short_executable_path_is_unchanged() {
        let path = Path::new(r"C:\Morphir\morphir-desktop.exe");
        assert_eq!(executable_path(path).unwrap(), path);
    }

    #[test]
    fn unavailable_or_unshortened_names_report_how_to_recover() {
        let path = PathBuf::from(format!(r"C:\{}\morphir-desktop.exe", "x".repeat(260)));
        for result in [
            Ok(path.clone()),
            Err(io::Error::other("short names unavailable")),
        ] {
            let error = bounded_executable_path(&path, |_| result)
                .unwrap_err()
                .to_string();
            assert!(error.contains("MORPHIR_HOME"), "{error}");
            assert!(error.contains("reinstall"), "{error}");
        }
    }

    #[test]
    fn executable_limit_counts_utf16_not_utf8_bytes() {
        let path = PathBuf::from(format!(r"C:\{}\desktop.exe", "é".repeat(150)));
        assert_eq!(
            bounded_executable_path(&path, |_| panic!("short path not needed")).unwrap(),
            path
        );
        let path = PathBuf::from(format!(r"C:\{}\desktop.exe", "🦀".repeat(130)));
        assert!(bounded_executable_path(&path, |_| Err(io::Error::other("unavailable"))).is_err());
    }
}
