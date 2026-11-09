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
//! Tool release metadata v1, extension release descriptors, capability
//! claims, MEP and Morphir IR keep their own versions. These readers parse
//! documents at the boundary into domain types and report a stable
//! [`Code`] with the member path for every refusal. They implement no
//! acquisition, network or filesystem behavior; the `morphirup`
//! implementation in finos/morphir-dotnet does.
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
mod result;

pub use diagnostic::{Code, Diagnostic, Result};
pub use envelope::{CONTRACT_VERSION, SUPPORTED_VERSIONS};
pub use ids::{
    CommandName, DeploymentId, ExtensionIdentity, GenerationId, ImplementationId, LanguageId,
    ModelToken, PackageId, PackageManagerId, PresetId, ProtocolVersion, Sha256, TargetDigest,
    TargetPath, WasmAbi, WorkflowId,
};
pub use lock::{LockedHost, PlatformClosure, ToolchainLock, read_lock};
pub use model::{
    DeliveryKind, LockedDelivery, LockedProvider, ModelInput, ModelTuple, Operation, Prerequisite,
    Protocol, RecipeRef, SdkPhase,
};
pub use platform::{Arch, Os, PlatformId};
pub use receipt::{
    Authentication, Check, CheckKind, CheckStatus, ClaimCheck, DotnetToolScope, HostIdentity,
    Installation, InstallationReceipt, InstalledHost, InstalledProvider, Launch, Ownership,
    ProbeSource, Readiness, RuntimeOrigin, read_receipt,
};
pub use recipe::{
    BuiltIn, Execution, HostOffering, HostSource, RecipeDelivery, RecipeProvider, ToolsetRecipe,
    read_recipe,
};
pub use request::{
    HostSelection, ProviderSelection, RequestedHost, ToolchainRequest, read_request,
};
pub use result::{
    COMMANDS, ComponentRef, ManagerResult, Outcome, ResultDiagnostic, ResultDiagnosticKind,
    SelectionSource, Severity, TRUST_CODES, canonical_sha256, read_result,
};

/// Understood `critical` member paths, by document.
pub mod understood {
    pub use crate::lock::UNDERSTOOD_PATHS as LOCK;
    pub use crate::receipt::UNDERSTOOD_PATHS as RECEIPT;
    pub use crate::recipe::UNDERSTOOD_PATHS as RECIPE;
    pub use crate::request::UNDERSTOOD_PATHS as REQUEST;
    pub use crate::result::UNDERSTOOD_PATHS as RESULT;
}
