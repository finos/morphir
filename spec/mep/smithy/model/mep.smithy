$version: "2"

// The Morphir Extension Protocol (MEP) as a Smithy model.
//
// This model is interim: later, Morphir defines the protocol in Morphir
// itself. The Gleam contract in spec/mep/contract/src/mep.gleam is the source
// of truth. This model follows it and its wire mapping in spec/mep/README.md.
// Member names are the wire names, so validation uses the default
// `--member-names smithy`.
//
// Scope: MEP 0.2.0-draft.1. That draft keeps every legacy 0.1 method and
// shape, and adds morphir.frontend.compileModel and
// morphir.backend.generateModel. One model covers both protocol versions.
//
// A comment that starts with `GAP smithy-` names an open beads issue in
// moonrockz/smithy. At that place, the smithy.rpc traits or the CLI cannot
// state or check the MEP rule. See spec/mep/smithy/README.md.
namespace morphir.mep

use smithy.rpc#jsonRpc
use smithy.rpc#jsonRpcCancels
use smithy.rpc#jsonRpcLifecycle
use smithy.rpc#jsonRpcProtocol
use smithy.rpc#jsonRpcSession
use smithy.rpc#method

// -- Protocol and session ----------------------------------------------------

/// A MEP session between a host and an extension.
///
/// The host sends requests and notifications to the extension. The extension
/// sends only `morphir.progress` to the host.
///
/// Lifecycle: starting -> initializing -> ready -> stopping -> stopped.
/// Before `morphir.initialize`, an extension accepts only
/// `morphir.initialize`, `morphir.extension.describe`, `morphir.ping` and
/// `morphir.exit`. After `morphir.shutdown`, it accepts only `morphir.exit`.
/// It refuses other requests in those states with -32014 (not initialized).
///
/// Each capability below is advertised when the value at its pointer in the
/// `morphir.initialize` result is present and not null or false.
// GAP smithy-2qe.34.19: the checker reports a request in the wrong state
// as StateViolation, but it cannot check that the extension refuses it with
// -32014. The same applies to -32013 for a capability that is not advertised.
// GAP smithy-2qe.34.20: a pointer cannot check that `protocolVersion`
// equals 0.2.0-draft.1, that `modelTransport.tuples` contains the method's
// operation, or that `extension.types` contains `validator` or `transform`.
@jsonRpcProtocol(
    versions: ["2.0"]
    peers: [
        { name: "host", accepts: HostService }
        { name: "extension", accepts: ExtensionService }
    ]
)
@jsonRpcSession(
    states: ["starting", "initializing", "ready", "stopping", "stopped"]
    capabilities: [
        { name: "cancellation", method: "morphir.initialize", pointer: "/capabilities/cancellation" }
        { name: "progress", method: "morphir.initialize", pointer: "/capabilities/progress" }
        { name: "frontend", method: "morphir.initialize", pointer: "/capabilities/frontend" }
        { name: "frontendCompile", method: "morphir.initialize", pointer: "/capabilities/frontend/compile" }
        { name: "backend", method: "morphir.initialize", pointer: "/capabilities/backend" }
        { name: "backendGenerate", method: "morphir.initialize", pointer: "/capabilities/backend/generate" }
        { name: "workspaceDiscover", method: "morphir.initialize", pointer: "/capabilities/workspace/discover" }
        { name: "modelTransport", method: "morphir.initialize", pointer: "/capabilities/modelTransport" }
    ]
)
structure MepSession {}

/// The methods that an extension accepts from its host.
// GAP smithy-2qe.34.15: the MEP error codes -32000 through -32004 and
// -32010 through -32014 are in the JSON-RPC server-error range. `rpcError`
// refuses codes from -32768 through -32000, so this service cannot declare
// them or the `data` of -32011. See ErrorCode.
@jsonRpc(versions: ["2.0"])
service ExtensionService {
    version: "0.2.0-draft.1"
    operations: [
        Initialize
        Describe
        Initialized
        Ping
        Info
        Capabilities
        Compile
        CompileModel
        Generate
        GenerateModel
        Validate
        Transform
        WorkspaceDiscover
        Shutdown
        Exit
        CancelRequest
    ]
}

/// The methods that a host accepts from its extension.
@jsonRpc(versions: ["2.0"])
service HostService {
    version: "0.2.0-draft.1"
    operations: [
        Progress
    ]
}

// -- Lifecycle methods -------------------------------------------------------

/// Negotiate the protocol version, identity and capabilities.
///
/// A failed initialize opens no session. A second initialize in a session is
/// refused with -32600.
@method(name: "morphir.initialize", params: "named")
@jsonRpcLifecycle(allowedIn: ["starting"], onSuccess: "initializing")
operation Initialize {
    input: InitializeParams
    output: InitializeResult
}

/// Read the extension's capability claim set, with no side effects. It is
/// allowed before `morphir.initialize` and in each later state before
/// shutdown. It is optional for an extension.
@method(name: "morphir.extension.describe", params: "named")
@jsonRpcLifecycle(allowedIn: ["starting", "initializing", "ready"])
operation Describe {
    input: DescribeParams
    output: CapabilityClaimSet
}

/// Tell the extension that the host accepted the handshake. A notification.
// GAP smithy-2qe.34.16: no trait marks this method as notification
// only, so a request with an `id` is accepted and then waits for a reply.
@method(name: "morphir.initialized", params: "named", nullResult: true)
@jsonRpcLifecycle(allowedIn: ["initializing"], onCall: "ready")
operation Initialized {
    input: EmptyParams
}

/// Check that the extension can respond. The contract does not define the
/// result; the Rust SDK sends `{"ok": true}`.
@method(name: "morphir.ping", params: "named", resultMember: "result")
@jsonRpcLifecycle(allowedIn: ["starting", "initializing", "ready"])
operation Ping {
    input: EmptyParams
    output: OpaqueResult
}

/// Read extension identity and version after initialization.
@method(name: "morphir.extension.info", params: "named")
@jsonRpcLifecycle(allowedIn: ["initializing", "ready"])
operation Info {
    input: EmptyParams
    output: ExtensionInfo
}

/// Read the negotiated capabilities after initialization.
@method(name: "morphir.extension.capabilities", params: "named")
@jsonRpcLifecycle(allowedIn: ["initializing", "ready"])
operation Capabilities {
    input: EmptyParams
    output: ExtensionCapabilities
}

/// Ask the extension to stop accepting work. After this request, the
/// extension accepts only `morphir.exit`. The contract does not define the
/// result; the Rust SDK sends `{}`.
@method(name: "morphir.shutdown", params: "named", resultMember: "result")
@jsonRpcLifecycle(allowedIn: ["initializing", "ready"], onCall: "stopping")
operation Shutdown {
    input: EmptyParams
    output: OpaqueResult
}

/// End the session. A notification, allowed in every state.
// GAP smithy-2qe.34.16: a request with an `id` is accepted.
@method(name: "morphir.exit", params: "named", nullResult: true)
@jsonRpcLifecycle(onCall: "stopped")
operation Exit {
    input: EmptyParams
}

// -- Cancellation and progress ----------------------------------------------

/// Ask the extension to cancel an active request of the host. A
/// notification. The host sends it only when the extension advertises
/// `cancellation`. The cancelled request may then fail with -32800.
// GAP smithy-2qe.34.16: a request with an `id` is accepted.
@method(name: "$/cancelRequest", params: "named", nullResult: true)
@jsonRpcLifecycle(requires: ["cancellation"])
@jsonRpcCancels(idMember: "id", code: -32800)
operation CancelRequest {
    input: CancelParams
}

/// Report progress for an active request of the host. A notification. The
/// extension sends it only when it advertises `progress`.
// GAP smithy-2qe.34.16: a request with an `id` is accepted.
// GAP smithy-2qe.34.24: nothing checks that `requestId` names an
// active request of the host.
@method(name: "morphir.progress", params: "named", nullResult: true)
@jsonRpcLifecycle(requires: ["progress"])
operation Progress {
    input: ProgressParams
}

/// Parameters of `$/cancelRequest`: the id of the request to cancel.
/// Cancellation is cooperative.
structure CancelParams {
    @required
    id: RequestId
}

/// Parameters of `morphir.progress`.
structure ProgressParams {
    @required
    requestId: RequestId

    @required
    kind: ProgressKind

    @required
    message: String

    /// Left out when absent.
    @range(min: 0, max: 100)
    percentage: Integer
}

/// The stage of a progress report.
enum ProgressKind {
    BEGIN = "begin"
    REPORT = "report"
    END = "end"
}

// -- Capability methods ------------------------------------------------------

/// Compile source documents to Morphir IR. Legacy 0.1 operation.
// GAP smithy-2qe.34.24: nothing checks that a `baseline` goes only to
// a frontend with `incremental: true`, that `options.irVersion` is in
// `irVersions`, or that more than one document goes only to a frontend with
// `multiDocument: true`.
@method(name: "morphir.frontend.compile", params: "named")
@jsonRpcLifecycle(allowedIn: ["ready"], requires: ["frontendCompile"])
operation Compile {
    input: CompileRequest
    output: CompileResult
}

/// Compile a source set to a complete model. Requires the exact MEP
/// 0.2.0-draft.1 session and an admitted compileModel tuple.
// GAP smithy-2qe.34.20: the session must use 0.2.0-draft.1 and its
// tuples must contain morphir.frontend.compileModel.
@method(name: "morphir.frontend.compileModel", params: "named")
@jsonRpcLifecycle(allowedIn: ["ready"], requires: ["frontend", "modelTransport"])
operation CompileModel {
    input: CompileModelRequest
    output: CompileModelResult
}

/// Generate artifacts from Morphir IR. Legacy 0.1 operation.
@method(name: "morphir.backend.generate", params: "named")
@jsonRpcLifecycle(allowedIn: ["ready"], requires: ["backendGenerate"])
operation Generate {
    input: GenerateRequest
    output: GenerateResult
}

/// Generate artifacts from a retained model. Requires the exact MEP
/// 0.2.0-draft.1 session and an admitted generateModel tuple.
// GAP smithy-2qe.34.20: the session must use 0.2.0-draft.1 and its
// tuples must contain morphir.backend.generateModel.
@method(name: "morphir.backend.generateModel", params: "named")
@jsonRpcLifecycle(allowedIn: ["ready"], requires: ["backend", "modelTransport"])
operation GenerateModel {
    input: GenerateModelRequest
    output: GenerateResult
}

/// Validate Morphir IR. The contract does not specify the payloads yet.
// GAP smithy-2qe.34.20: `extension.types` must contain `validator`.
// GAP smithy-2qe.34.25: no trait makes the params any JSON value, as
// `resultMember` does for a result, so each params member is unknown.
@method(name: "morphir.validator.validate", params: "named", resultMember: "result")
@jsonRpcLifecycle(allowedIn: ["ready"])
operation Validate {
    input: EmptyParams
    output: OpaqueResult
}

/// Transform Morphir IR to Morphir IR. The contract does not specify the
/// payloads yet.
// GAP smithy-2qe.34.20: `extension.types` must contain `transform`.
// GAP smithy-2qe.34.25: the params cannot be any JSON value.
@method(name: "morphir.transform.transform", params: "named", resultMember: "result")
@jsonRpcLifecycle(allowedIn: ["ready"])
operation Transform {
    input: EmptyParams
    output: OpaqueResult
}

/// Discover workspace members. The payloads live in morphir_workspace, not
/// in this contract.
// GAP smithy-2qe.34.25: the params cannot be any JSON value.
@method(name: "morphir.workspace.discover", params: "named", resultMember: "result")
@jsonRpcLifecycle(allowedIn: ["ready"], requires: ["workspaceDiscover"])
operation WorkspaceDiscover {
    input: EmptyParams
    output: OpaqueResult
}

/// Parameters with no members. The params can be absent or `{}`.
structure EmptyParams {}

/// A result that the contract does not constrain. The JSON-RPC `result` is
/// the value of `result`.
structure OpaqueResult {
    result: Document
}

// -- Shared values -----------------------------------------------------------

/// A JSON-RPC 2.0 request id: a non-negative integer or a string, written as
/// the value itself. The Rust SDK sends numeric ids only.
// GAP smithy-2qe.34.22: Smithy has no untagged union of a number and a
// string, so this is a Document, and an object or a boolean is accepted.
document RequestId

/// Any JSON value, written as that value. Used where the protocol carries
/// data that the contract does not constrain, such as compiled IR.
document Json

/// A JSON object with any members.
map JsonObject {
    key: String
    value: Json
}

/// A list of strings.
list StringList {
    member: String
}

/// A JSON-RPC 2.0 error code that MEP uses. The wire value is the integer.
///
/// The first five are the JSON-RPC 2.0 standard codes. -32000 through -32014
/// are MEP codes in the server-error range, -32099 through -32000.
/// -32800 is the code of a cancelled request, as in the Language Server
/// Protocol.
// GAP smithy-2qe.34.15: only -32800 is outside the reserved range, and it
// is declared through `jsonRpcCancels` on CancelRequest. The validator
// accepts every server-error code on every method without a data check.
intEnum ErrorCode {
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    EXTENSION_ERROR = -32000
    COMPILATION_ERROR = -32001
    GENERATION_ERROR = -32002
    VALIDATION_ERROR = -32003
    TRANSFORMATION_ERROR = -32004
    EXTENSION_FAILURE = -32010
    PROTOCOL_VERSION_MISMATCH = -32011
    PERMISSION_DENIED = -32012
    CAPABILITY_UNAVAILABLE = -32013
    NOT_INITIALIZED = -32014
    REQUEST_CANCELLED = -32800
}

/// The JSON-RPC 2.0 error object, for code generation. `code` is an
/// ErrorCode value or another JSON-RPC 2.0 code, a signed 32-bit integer.
/// `data` is left out when absent. The validator checks the error envelope
/// itself.
structure RpcError {
    @required
    code: Integer

    @required
    message: String

    data: Json
}
