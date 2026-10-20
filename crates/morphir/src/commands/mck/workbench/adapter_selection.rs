//! Explicit Workbench adapter selection at the CLI boundary.

use std::ffi::{OsStr, OsString};

/// Executable arguments are borrowed unchanged until the actual process launch.
#[derive(Debug, PartialEq, Eq)]
pub(super) enum WorkbenchAdapter<'a> {
    BuiltinNativeWorkbench,
    External {
        program: &'a OsStr,
        arguments: &'a [OsString],
    },
}

#[derive(Debug, PartialEq, Eq)]
pub(super) enum AdapterSelectionError {
    BuiltinArguments,
}

impl WorkbenchAdapter<'_> {
    pub(super) fn parse<'a>(
        program: &'a OsStr,
        arguments: &'a [OsString],
    ) -> Result<WorkbenchAdapter<'a>, AdapterSelectionError> {
        if program == OsStr::new("builtin:morphir-workbench") {
            if arguments.is_empty() {
                Ok(WorkbenchAdapter::BuiltinNativeWorkbench)
            } else {
                Err(AdapterSelectionError::BuiltinArguments)
            }
        } else {
            Ok(WorkbenchAdapter::External { program, arguments })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::{OsStr, OsString};

    #[test]
    fn exact_reserved_selector_chooses_native_without_an_external_program() {
        assert_eq!(
            WorkbenchAdapter::parse(OsStr::new("builtin:morphir-workbench"), &[]),
            Ok(WorkbenchAdapter::BuiltinNativeWorkbench),
        );
    }

    #[test]
    fn builtin_arguments_are_refused_instead_of_ignored() {
        let arguments = [OsString::from("--anything")];
        assert_eq!(
            WorkbenchAdapter::parse(OsStr::new("builtin:morphir-workbench"), &arguments),
            Err(AdapterSelectionError::BuiltinArguments),
        );
    }

    #[test]
    fn external_executable_and_each_argument_remain_verbatim() {
        let program = OsStr::new("path with spaces/adapter");
        let arguments = [
            OsString::from("--one=a b"),
            OsString::from(""),
            OsString::from("$(literal)"),
        ];
        assert_eq!(
            WorkbenchAdapter::parse(program, &arguments),
            Ok(WorkbenchAdapter::External {
                program,
                arguments: &arguments
            }),
        );
    }

    #[test]
    fn explicit_path_spelling_is_not_normalized_to_a_builtin() {
        for program in [
            "./builtin:morphir-workbench",
            "/tmp/builtin:morphir-workbench",
            "builtin:morphir-workbench ",
            "Builtin:morphir-workbench",
            "",
        ] {
            assert_eq!(
                WorkbenchAdapter::parse(OsStr::new(program), &[]),
                Ok(WorkbenchAdapter::External {
                    program: OsStr::new(program),
                    arguments: &[]
                }),
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn unix_non_unicode_program_and_argument_bytes_are_preserved() {
        use std::os::unix::ffi::OsStringExt as _;
        let program = OsString::from_vec(b"adapter-\xff".to_vec());
        let arguments = [OsString::from_vec(b"argument-\xfe".to_vec())];
        assert_eq!(
            WorkbenchAdapter::parse(&program, &arguments),
            Ok(WorkbenchAdapter::External {
                program: &program,
                arguments: &arguments
            }),
        );
    }

    #[cfg(windows)]
    #[test]
    fn windows_unpaired_utf16_program_and_argument_units_are_preserved() {
        use std::os::windows::ffi::OsStringExt as _;
        let program = OsString::from_wide(&[97, 0xd800]);
        let arguments = [OsString::from_wide(&[98, 0xdc00])];
        assert_eq!(
            WorkbenchAdapter::parse(&program, &arguments),
            Ok(WorkbenchAdapter::External {
                program: &program,
                arguments: &arguments
            }),
        );
    }
}

#[cfg(test)]
mod installed_controls;
