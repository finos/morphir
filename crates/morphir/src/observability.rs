//! Correlation identifiers shared by CLI operations and launched components.

use std::fmt;

/// Environment variable used to pass a parent operation to a child process.
pub const PARENT_OPERATION_ID_ENV: &str = "MORPHIR_PARENT_OPERATION_ID";

/// Environment variable used to correlate one managed Desktop process launch.
pub const LAUNCH_ID_ENV: &str = "MORPHIR_LAUNCH_ID";

/// An opaque identifier for one user-requested Morphir operation.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct OperationId(String);

impl OperationId {
    /// Create a new identifier without encoding user, host, or command data.
    pub fn new() -> Self {
        Self(format!("op-{}", uuid::Uuid::new_v4()))
    }

    /// Return the identifier as a string slice for structured fields and child processes.
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Parse an identifier previously reported by Morphir.
    pub fn parse(value: &str) -> Option<Self> {
        let uuid = uuid::Uuid::parse_str(value.strip_prefix("op-")?).ok()?;
        Some(Self(format!("op-{uuid}")))
    }
}

impl Default for OperationId {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for OperationId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// An opaque identifier for one attempt to launch a managed component.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct LaunchId(String);

impl LaunchId {
    /// Create a new identifier without encoding user, host, path, or tool data.
    pub fn new() -> Self {
        Self(format!("launch-{}", uuid::Uuid::new_v4()))
    }

    /// Return the identifier as a string slice for structured fields and child processes.
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// Parse an identifier previously written by a Morphir launcher.
    pub fn parse(value: &str) -> Option<Self> {
        let uuid = uuid::Uuid::parse_str(value.strip_prefix("launch-")?).ok()?;
        Some(Self(format!("launch-{uuid}")))
    }
}

impl Default for LaunchId {
    fn default() -> Self {
        Self::new()
    }
}

impl fmt::Display for LaunchId {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(self.as_str())
    }
}

/// Correlation values owned by the CLI for one managed Desktop launch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DesktopLaunchContext {
    operation_id: OperationId,
    launch_id: LaunchId,
}

impl DesktopLaunchContext {
    /// Start a launch beneath an existing user-requested CLI operation.
    pub fn new(operation_id: &OperationId) -> Self {
        Self::from_ids(operation_id.clone(), LaunchId::new())
    }

    /// Reconstruct a known launch, primarily for deterministic process and integration tests.
    pub fn from_ids(operation_id: OperationId, launch_id: LaunchId) -> Self {
        Self {
            operation_id,
            launch_id,
        }
    }

    /// The CLI operation that owns this launch.
    pub fn operation_id(&self) -> &OperationId {
        &self.operation_id
    }

    /// The identifier unique to this process launch attempt.
    pub fn launch_id(&self) -> &LaunchId {
        &self.launch_id
    }

    /// The complete correlation pair to add to the Desktop child environment.
    pub fn child_environment(&self) -> [(&'static str, &str); 2] {
        [
            (PARENT_OPERATION_ID_ENV, self.operation_id.as_str()),
            (LAUNCH_ID_ENV, self.launch_id.as_str()),
        ]
    }
}

/// Stable Desktop lifecycle event names consumed by launchers and diagnostic tools.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DesktopLaunchEvent {
    Ready,
    LaunchFailed,
    Crash,
    Exit,
}

impl DesktopLaunchEvent {
    /// Return the version-one JSON Lines event name.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Ready => "desktop.ready",
            Self::LaunchFailed => "desktop.launch.failed",
            Self::Crash => "desktop.crash",
            Self::Exit => "desktop.exit",
        }
    }

    /// Recognize a lifecycle event from a Desktop JSON Lines record.
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "desktop.ready" => Some(Self::Ready),
            "desktop.launch.failed" => Some(Self::LaunchFailed),
            "desktop.crash" => Some(Self::Crash),
            "desktop.exit" => Some(Self::Exit),
            _ => None,
        }
    }
}

/// Stable failure codes emitted by the CLI side of the Desktop launch handshake.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum DesktopLaunchErrorCode {
    SpawnFailed,
    ReadyTimedOut,
    ExitedBeforeReady,
}

impl DesktopLaunchErrorCode {
    /// Return the version-one diagnostic code.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::SpawnFailed => "MORPHIR_DESKTOP_SPAWN_FAILED",
            Self::ReadyTimedOut => "MORPHIR_DESKTOP_READY_TIMEOUT",
            Self::ExitedBeforeReady => "MORPHIR_DESKTOP_EXIT_BEFORE_READY",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn operation_ids_are_opaque_unique_uuid_values() {
        let first = OperationId::new();
        let second = OperationId::new();

        assert_ne!(first, second);
        assert!(first.as_str().starts_with("op-"));
        uuid::Uuid::parse_str(first.as_str().trim_start_matches("op-")).unwrap();
        assert_eq!(OperationId::parse(first.as_str()), Some(first));
        assert!(OperationId::parse("bad-operation").is_none());
    }

    #[test]
    fn parsed_operation_ids_use_the_canonical_logged_spelling() {
        let canonical = "op-123e4567-e89b-42d3-a456-426614174abc";
        let uppercase = "op-123E4567-E89B-42D3-A456-426614174ABC";

        assert_eq!(OperationId::parse(uppercase).unwrap().as_str(), canonical);
    }

    #[test]
    fn launch_ids_are_opaque_unique_uuid_values() {
        let first = LaunchId::new();
        let second = LaunchId::new();

        assert_ne!(first, second);
        assert!(first.as_str().starts_with("launch-"));
        uuid::Uuid::parse_str(first.as_str().trim_start_matches("launch-")).unwrap();
        assert_eq!(LaunchId::parse(first.as_str()), Some(first));
        assert!(LaunchId::parse("bad-launch").is_none());
    }

    #[test]
    fn managed_desktop_launch_supplies_one_correlation_pair() {
        let operation_id = OperationId::parse("op-123e4567-e89b-42d3-a456-426614174000").unwrap();
        let launch_id = LaunchId::parse("launch-123e4567-e89b-42d3-a456-426614174001").unwrap();
        let launch = DesktopLaunchContext::from_ids(operation_id.clone(), launch_id.clone());
        let generated = DesktopLaunchContext::new(&operation_id);

        assert_eq!(launch.operation_id(), &operation_id);
        assert_eq!(launch.launch_id(), &launch_id);
        assert_eq!(generated.operation_id(), &operation_id);
        assert_ne!(generated.launch_id(), &launch_id);
        assert_eq!(
            launch.child_environment(),
            [
                (PARENT_OPERATION_ID_ENV, operation_id.as_str()),
                (LAUNCH_ID_ENV, launch_id.as_str()),
            ]
        );
    }

    #[test]
    fn desktop_launch_event_names_are_stable() {
        assert_eq!(DesktopLaunchEvent::Ready.as_str(), "desktop.ready");
        assert_eq!(
            DesktopLaunchEvent::LaunchFailed.as_str(),
            "desktop.launch.failed"
        );
        assert_eq!(DesktopLaunchEvent::Crash.as_str(), "desktop.crash");
        assert_eq!(DesktopLaunchEvent::Exit.as_str(), "desktop.exit");
        assert_eq!(
            DesktopLaunchEvent::parse("desktop.ready"),
            Some(DesktopLaunchEvent::Ready)
        );
        assert_eq!(DesktopLaunchEvent::parse("desktop.unknown"), None);
    }

    #[test]
    fn cli_launch_error_codes_are_stable() {
        assert_eq!(
            DesktopLaunchErrorCode::SpawnFailed.as_str(),
            "MORPHIR_DESKTOP_SPAWN_FAILED"
        );
        assert_eq!(
            DesktopLaunchErrorCode::ReadyTimedOut.as_str(),
            "MORPHIR_DESKTOP_READY_TIMEOUT"
        );
        assert_eq!(
            DesktopLaunchErrorCode::ExitedBeforeReady.as_str(),
            "MORPHIR_DESKTOP_EXIT_BEFORE_READY"
        );
    }
}
