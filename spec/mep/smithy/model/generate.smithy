$version: "2"

// Backend generation and diagnostics. See mep.smithy for the scope and the
// meaning of `GAP smithy-` comments.
namespace morphir.mep

// -- Generate ---------------------------------------------------------------

/// Parameters of `morphir.backend.generate`. `target` is the exact target id
/// that the host selected. A backend does not guess a default.
structure GenerateRequest {
    @required
    ir: Json

    @required
    target: String

    /// Read as empty when absent.
    options: JsonObject = {}
}

/// Result of `morphir.backend.generate` and `morphir.backend.generateModel`.
structure GenerateResult {
    @required
    success: Boolean

    artifacts: ArtifactList = []

    diagnostics: DiagnosticList = []
}

/// A generated file. `path` is relative to the output directory of the
/// host. When `binary` is true, `content` is base64; otherwise it is UTF-8
/// text.
structure Artifact {
    @required
    path: String

    @required
    content: String

    binary: Boolean = false
}

list ArtifactList {
    member: Artifact
}

// -- Diagnostics ------------------------------------------------------------

/// A diagnostic message.
structure Diagnostic {
    @required
    severity: DiagnosticSeverity

    /// A stable extension-specific identifier. Left out when absent.
    code: String

    @required
    message: String

    /// Left out when absent.
    location: SourceLocation

    /// Left out when empty.
    related: RelatedInformationList = []

    /// Structured data that the extension owns. Left out when absent.
    data: Json
}

list DiagnosticList {
    member: Diagnostic
}

/// How serious a diagnostic is.
enum DiagnosticSeverity {
    ERROR = "error"
    WARNING = "warning"
    INFO = "info"
    HINT = "hint"
}

/// A range in a source document, identified by URI.
structure SourceLocation {
    @required
    uri: String

    @required
    range: SourceRange
}

/// A half-open range: `start` is inclusive and `end` is exclusive.
structure SourceRange {
    @required
    start: SourcePosition

    @required
    end: SourcePosition
}

/// A zero-based position. `character` counts UTF-16 code units from the
/// start of the line, as in the Language Server Protocol.
structure SourcePosition {
    @required
    @range(min: 0, max: 4294967295)
    line: Long

    @required
    @range(min: 0, max: 4294967295)
    character: Long
}

/// More information about a diagnostic, at another location.
structure RelatedInformation {
    @required
    location: SourceLocation

    @required
    message: String
}

list RelatedInformationList {
    member: RelatedInformation
}
