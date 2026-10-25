$version: "2"

// Frontend compilation, legacy 0.1 shapes. See mep.smithy for the scope and
// the meaning of `GAP smithy-` comments.
namespace morphir.mep

/// A source document sent to a frontend. The host sends the text by value.
structure SourceDocument {
    @required
    uri: String

    @required
    languageId: String

    /// Goes up each time that the document changes.
    @required
    @range(min: 0)
    version: Long

    @required
    text: String
}

list SourceDocumentList {
    member: SourceDocument
}

/// The package that a compilation builds.
structure CompilePackage {
    @required
    name: String

    /// Left out when absent. An absent list exposes every module; an empty
    /// list exposes none.
    exposedModules: StringList
}

/// A package distribution that the compilation can use. `distribution` is a
/// serialized Morphir distribution in the IR version that `irVersion` names.
structure CompileDependency {
    @required
    packageName: String

    @required
    irVersion: String

    @required
    distribution: Json
}

list CompileDependencyList {
    member: CompileDependency
}

/// Options that control a compilation.
// GAP smithy-2qe.34.18: the Gleam `extra` members sit beside
// `typesOnly` and `irVersion`. A reader refuses the legacy keys
// `sourceRootUri` and `sourceRoot`. Smithy cannot declare additional members
// or forbidden member names.
structure CompileOptions {
    @required
    typesOnly: Boolean

    @required
    irVersion: String
}

/// The documents that a compilation submits, with the root that module names
/// are derived against.
structure SourceSet {
    /// Left out when absent.
    root: String

    @required
    documents: SourceDocumentList
}

/// Parameters of `morphir.frontend.compile`.
///
/// `sources` is required. Unknown members are ignored, including a top-level
/// `documents`, which cannot replace `sources`.
structure CompileRequest {
    @required
    languageId: String

    @required
    sources: SourceSet

    @required
    package: CompilePackage

    /// Read as empty when absent.
    dependencies: CompileDependencyList = []

    @required
    options: CompileOptions

    /// Left out when absent. Only for a frontend with `incremental: true`.
    baseline: CompileBaseline
}

/// Result of `morphir.frontend.compile`. A compilation failure is a normal
/// result with `success: false`, not a JSON-RPC error.
structure CompileResult {
    @required
    success: Boolean

    irVersion: String

    /// The Morphir IR distribution as JSON, not a JSON-encoded string.
    ir: Json

    diagnostics: DiagnosticList = []

    modules: StringList = []

    /// Left out when empty.
    moduleResults: ModuleResultList = []

    contextDigest: String
}

/// A module from an earlier compilation, sent back for incremental
/// compilation.
structure BaselineModule {
    @required
    name: String

    @required
    uri: String

    @required
    sourceDigest: String

    @required
    interfaceDigest: String

    dependsOn: StringList = []

    @required
    ir: Json

    frontendState: Json
}

list BaselineModuleList {
    member: BaselineModule
}

/// The baseline that a host sends for incremental compilation. A baseline
/// without `contextDigest` cannot be reused.
structure CompileBaseline {
    modules: BaselineModuleList = []

    contextDigest: String
}

/// The outcome for one module in an incremental compilation.
enum ModuleStatus {
    COMPILED = "compiled"
    UNCHANGED = "unchanged"
    FAILED = "failed"
    BLOCKED = "blocked"
}

/// The result for one module in an incremental compilation.
structure ModuleResult {
    @required
    name: String

    @required
    uri: String

    @required
    status: ModuleStatus

    sourceDigest: String

    interfaceDigest: String

    dependsOn: StringList = []

    /// Present only when `status` is `compiled`.
    ir: Json

    frontendState: Json

    diagnostics: DiagnosticList = []
}

list ModuleResultList {
    member: ModuleResult
}
