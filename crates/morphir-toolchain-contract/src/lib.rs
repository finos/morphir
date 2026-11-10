//! Reference readers for the shared morphirup acquisition contracts.
//!
//! Five documents start at `0.1.0-draft.1`, each versioned by its own
//! specification under `docs/spec/toolchain/`:
//!
//! | Document | Where it lives | Reader |
//! | --- | --- | --- |
//! | Toolset recipe | Authenticated TUF target | [`read_recipe`] |
//! | Project toolchain request | `.morphir/toolchain.toml` | [`read_request`] |
//! | Portable lock | `.morphir/toolchain.lock.json` | [`read_lock`] |
//! | Installation receipt | `MORPHIR_HOME/toolchains/generations/<id>/` | [`read_receipt`] |
//! | Manager result | `morphirup --json` standard output | [`read_result`] |
//!
//! This crate is this repository's reference reader for those document
//! contracts: ordinary schema and conformance testing, not a compatibility
//! runner. The contract itself is the specification pages, schemas, fixtures
//! and case manifests; every rule this crate enforces is stated there.
//!
//! ```
//! use morphir_toolchain_contract::{Code, read_request};
//!
//! let request = br#"schemaVersion = "0.1.0-draft.2"
//! [host]
//! implementation = "dotnet"
//! deployment = "native-aot"
//! channel = "stable"
//! [toolset]
//! preset = "fsharp"
//! "#;
//! let refused = read_request(request).unwrap_err();
//! assert_eq!(refused.code, Code::UnsupportedContractVersion);
//! assert_eq!(refused.path, "schemaVersion");
//! ```

mod authenticated;
mod diagnostic;
mod envelope;
mod ids;
mod lock;
mod model;
mod platform;
mod reader;
mod receipt;
mod recipe;
mod request;
mod resolve;
mod result;

pub use authenticated::{AuthenticatedTargets, RecipeStatus, RecipeTargetState};
pub use diagnostic::{Code, Diagnostic, DiagnosticKind, Result};
pub use envelope::{CONTRACT_VERSION, SUPPORTED_VERSIONS};
pub use ids::{
    AbsolutePath, CommandName, DeploymentId, ExtensionIdentity, GenerationId, ImplementationId,
    LanguageId, ModelToken, PackageId, PackageManagerId, PathStyle, PresetId, ProtocolVersion,
    Sha256, TargetDigest, TargetPath, WasmAbi, WorkflowId,
};
pub use lock::{LockedHost, PlatformClosure, RequestChangeCause, ToolchainLock, read_lock};
pub use model::{
    DeliveryKind, LockedDelivery, LockedProvider, ModelInput, ModelTuple, Operation, Prerequisite,
    Protocol, RecipeRef, SdkPhase,
};
pub use platform::{Arch, Os, PlatformId};
pub use receipt::{
    Authentication, Check, CheckKind, CheckStatus, ClaimCheck, DotnetToolScope, HostExecution,
    HostIdentity, Installation, InstallationReceipt, InstalledHost, InstalledProvider, Launch,
    ManagedRuntime, Ownership, ProbeSource, Readiness, read_receipt,
};
pub use recipe::{
    BuiltIn, Execution, HostOffering, HostSource, RecipeDelivery, RecipeProvider, ToolsetRecipe,
    read_recipe,
};
pub use request::{
    HostSelection, ProviderSelection, RequestedHost, ToolchainRequest, read_request,
};
pub use resolve::resolve_closure;
pub use result::{
    Alternative, Command, ComponentRef, DocumentKind, ManagerResult, MetadataRefresh, Outcome,
    Plan, PlanComponent, PlanSource, Probe, ResultDiagnostic, ResultDiagnosticKind, Selection,
    SelectionSource, Severity, TufRole, canonical_json, canonical_sha256, read_result,
};

/// Understood `critical` member paths, by document.
pub mod understood {
    pub use crate::lock::UNDERSTOOD_PATHS as LOCK;
    pub use crate::receipt::UNDERSTOOD_PATHS as RECEIPT;
    pub use crate::recipe::UNDERSTOOD_PATHS as RECIPE;
    pub use crate::request::UNDERSTOOD_PATHS as REQUEST;
    pub use crate::result::UNDERSTOOD_PATHS as RESULT;
}
