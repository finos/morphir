//! Static source roles. Names here are symbols, never live handles or grants.
use super::walk::{Operand, Site};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Role {
    Grant,
    Guest,
    Provider,
    ProviderProject,
    File,
    LiteralPeer,
    NativeRuntime,
    ExecutionRuntime,
    Connection,
    CaptureAttempt,
    Capture,
    PendingCapture,
    Writer,
    Checkpoint,
    MessageProbe,
    OpeningAttempt,
    Model,
    Execution,
    LocalEvaluationAttempt,
    PendingLocalEvaluation,
    PendingNativeInitialize,
    PendingNativeChoose,
    NativeProject,
    PendingNativeOpen,
    PendingConnectedOpening,
    ExpectedBytes,
    ExpectedRich,
    ExpectedTrace,
    ExpectedCheck,
    ExpectedBinding,
    ExpectedObligation,
    ExpectedEntry,
    ExpectedWork,
    ExpectedLockActor,
    ObservedConnection,
    ObservedCapture,
    ObservedRegistration,
    ObservedWork,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum SemanticBlocker {
    /// V27 does not yet specify which incoming owner this alias denotes.
    ReplaceIncoming,
    ConceptualOriginalOwner,
    /// No actual server EffectRef issuer has yet been bound at this source site.
    UnboundServerEffectIssuer(Site),
    /// A complete static site has been visited but has no approved meaning yet.
    UnclassifiedSite(Site),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Meaning {
    Define(Role),
    Reference(Role),
    Prearm(Role),
    /// An actual EffectRef.kind determines the permitted typed subject roles.
    EffectSubject,
    CountSubject,
    NativeBoundaryPending,
    /// Compilation records an equality obligation. It creates no runtime owner.
    ObservationClaim {
        role: Role,
        scope: ObservationScope,
    },
    /// The alias is observational and needs the enclosing expected local scope.
    LocalDefine(Role),
    LocalReference(Role),
    Blocked(SemanticBlocker),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ObservationScope {
    OpeningAttempt,
    ConnectionProvider,
    CaptureAttempt,
}

pub(super) fn classify(site: Site) -> Meaning {
    use Meaning::{
        Blocked, Define, EffectSubject, LocalDefine, LocalReference, NativeBoundaryPending, Prearm,
        Reference,
    };
    use Role::*;
    match site.parts() {
        (Operand::Input, "HostFixtureGrantsItem", None, "alias") => Define(Grant),
        (Operand::Input, "Guest", None, "alias") => Define(Guest),
        (Operand::Input, "Provider", Some("native" | "installed"), "alias") => Define(Provider),
        (Operand::Input, "Provider", Some("native" | "installed"), "grant") => Reference(Grant),
        (Operand::Input, "Provider", Some("installed"), "guest") => Reference(Guest),
        (Operand::Input, "ProjectBinding", None, "alias") => Define(ProviderProject),
        (Operand::Input, "HostFixtureRecordsItem", None, "grant")
        | (Operand::Input, "HostFixtureStartup", None, "cwd")
        | (Operand::Input, "HostFixtureStartupOutputOverride", Some("explicit"), "grant") => {
            Reference(Grant)
        }
        (Operand::Input, "ClientFixtureFilesItem", None, "alias") => Define(File),
        (Operand::Input, "ClientFixtureLiteralPeersItem", None, "alias") => Define(LiteralPeer),
        (
            Operand::Input,
            "ClientRuntime",
            Some(
                "controlled-http-executions"
                | "controlled-model-originals-http-v1"
                | "controlled-native-workspace-v1",
            ),
            "peer",
        ) => Reference(LiteralPeer),
        (Operand::Input, "ClientRuntime", Some("controlled-native-workspace-v1"), "runtime") => {
            Define(NativeRuntime)
        }
        (Operand::Input, "HostAction", Some("connect"), "connection") => Define(Connection),
        (
            Operand::Input,
            "HostAction",
            Some("capture-selected" | "begin-capture-selected"),
            "attempt",
        ) => Define(CaptureAttempt),
        (
            Operand::Input,
            "HostAction",
            Some("capture-selected" | "begin-capture-selected"),
            "capture",
        ) => Define(Capture),
        (Operand::Input, "HostAction", Some("begin-capture-selected"), "pending") => {
            Define(PendingCapture)
        }
        (Operand::Input, "HostAction", Some("start-cooperating-compile"), "writer") => {
            Define(Writer)
        }
        (Operand::Input, "HostAction" | "ClientAction", Some("checkpoint"), "name") => {
            Define(Checkpoint)
        }
        (Operand::Input, "HostAction", Some("producer-message-boundary"), "probe") => {
            Define(MessageProbe)
        }
        (Operand::Input, "HostAction", Some("hold"), "attempt") => Prearm(CaptureAttempt),
        (Operand::Input, "HostAction", Some("hold-cooperating-compile"), "writer") => {
            Prearm(Writer)
        }
        (Operand::Input, "HostAction", Some("continue"), "attempt") => Reference(CaptureAttempt),
        (Operand::Input, "HostAction", Some("await-capture"), "pending")
        | (Operand::Input, "HostActionAwaitBoundaryCaptureOwner", None, "pending") => {
            Reference(PendingCapture)
        }
        (
            Operand::Input,
            "HostAction",
            Some("await-cooperating-compile" | "continue-cooperating-compile"),
            "writer",
        )
        | (Operand::Input, "HostActionAwaitBoundaryWriterOwner", None, "writer") => {
            Reference(Writer)
        }
        (
            Operand::Input,
            "HostAction",
            Some(
                "discover"
                | "capture-selected"
                | "begin-capture-selected"
                | "open-legacy-selected"
                | "remove-provider"
                | "reoffer-same-labels",
            ),
            "provider",
        ) => Reference(Provider),
        (
            Operand::Input,
            "HostAction",
            Some("capture-selected" | "begin-capture-selected" | "open-legacy-selected"),
            "project",
        ) => Reference(ProviderProject),
        (
            Operand::Input,
            "HostAction",
            Some("inventory" | "read-selected" | "release"),
            "capture",
        ) => Reference(Capture),
        (
            Operand::Input,
            "HostAction",
            Some(
                "discover"
                | "capture-selected"
                | "begin-capture-selected"
                | "inventory"
                | "read-selected"
                | "release"
                | "send"
                | "disconnect"
                | "open-legacy-selected"
                | "producer-message-boundary",
            ),
            "connection",
        ) => Reference(Connection),
        (
            Operand::Input,
            "HostAction",
            Some("replace-project" | "replace-output"),
            "grant" | "replacement",
        )
        | (
            Operand::Input,
            "HostAction",
            Some("start-cooperating-compile" | "uncooperative-write"),
            "grant",
        ) => Reference(Grant),
        (Operand::Input, "ClientAction", Some("initialize-execution-runtime"), "attempt") => {
            Define(ExecutionRuntime)
        }
        (
            Operand::Input,
            "ClientAction",
            Some(
                "start-import"
                | "start-connected"
                | "begin-native-open-project"
                | "begin-connected-opening",
            ),
            "attempt",
        ) => Define(OpeningAttempt),
        (Operand::Input, "ClientAction", Some("bind-model-owner"), "model") => Define(Model),
        (Operand::Input, "ClientAction", Some("submit-execution"), "execution") => {
            Define(Execution)
        }
        (Operand::Input, "ClientAction", Some("begin-local-evaluation"), "attempt") => {
            Define(LocalEvaluationAttempt)
        }
        (Operand::Input, "ClientAction", Some("begin-local-evaluation"), "pending") => {
            Define(PendingLocalEvaluation)
        }
        (Operand::Input, "ClientAction", Some("begin-native-initialize"), "pending") => {
            Define(PendingNativeInitialize)
        }
        (Operand::Input, "ClientAction", Some("begin-native-choose"), "pending") => {
            Define(PendingNativeChoose)
        }
        (Operand::Input, "ClientAction", Some("bind-native-project"), "project") => {
            Define(NativeProject)
        }
        (Operand::Input, "ClientAction", Some("begin-native-open-project"), "pending") => {
            Define(PendingNativeOpen)
        }
        (Operand::Input, "ClientAction", Some("begin-connected-opening"), "pending") => {
            Define(PendingConnectedOpening)
        }
        (Operand::Input, "ClientAction", Some("replace-model"), "incoming") => {
            Blocked(SemanticBlocker::ReplaceIncoming)
        }
        (
            Operand::Input,
            "ClientAction",
            Some("bind-model-owner" | "cancel-opening" | "mutate-caller"),
            "attempt",
        ) => Reference(OpeningAttempt),
        (
            Operand::Input,
            "ClientAction",
            Some(
                "inspect"
                | "search"
                | "conceptual-specification"
                | "download-original"
                | "download-archive"
                | "close-model"
                | "replace-model"
                | "submit-execution"
                | "select-current-declaration"
                | "begin-local-evaluation",
            ),
            "model",
        ) => Reference(Model),
        (Operand::Input, "ClientAction", Some("release-execution"), "execution") => {
            Reference(Execution)
        }
        (Operand::Input, "ClientAction", Some("await-local-evaluation"), "pending") => {
            Reference(PendingLocalEvaluation)
        }
        (
            Operand::Input,
            "ClientAction",
            Some(
                "begin-native-initialize"
                | "begin-native-choose"
                | "begin-native-open-project"
                | "dispose-native-runtime"
                | "await-native-disposal",
            ),
            "runtime",
        ) => Reference(NativeRuntime),
        (Operand::Input, "ClientAction", Some("bind-native-project"), "choice") => {
            Reference(PendingNativeChoose)
        }
        (Operand::Input, "ClientAction", Some("begin-native-open-project"), "project") => {
            Reference(NativeProject)
        }
        (
            Operand::Input,
            "ClientAction",
            Some(
                "await-connected-boundary"
                | "dispose-connected-opening"
                | "await-connected-disposal",
            ),
            "pending",
        ) => Reference(PendingConnectedOpening),
        (Operand::Input, "PickerSignal" | "DeliveredReply", Some("file-selection"), "file") => {
            Reference(File)
        }
        (Operand::Input | Operand::Expected, "EffectRef", None, "attempt") => EffectSubject,
        (Operand::Expected, "ExpectedClientCheck", Some("port-counts"), "attempts") => {
            Meaning::CountSubject
        }
        // The same runtime spelling may refer to initialize/choose/open pending
        // kinds. The actual AwaitNativeBoundary.boundary is required to select.
        (Operand::Input, "ClientAction", Some("await-native-boundary"), "pending") => {
            NativeBoundaryPending
        }
        // ReadRun.source must resolve only in fixture input; never expected data.
        (Operand::Input, "ReadRun", None, "source")
        | (Operand::Input, "ClientAction", Some("read-run"), "source") => Reference(File),
        (Operand::Input, "ReadRun", None, "attempt")
        | (Operand::Input, "ClientAction", Some("read-run"), "attempt") => {
            Reference(OpeningAttempt)
        }
        (Operand::Expected, "ExpectedByteSource", None, "alias") => Define(ExpectedBytes),
        (
            Operand::Expected,
            "ExpectedWorkflowModelOriginalsServerRichSourcesItem"
            | "ExpectedWorkflowModelOriginalsClientRichSourcesItem",
            None,
            "alias",
        ) => Define(ExpectedRich),
        (
            Operand::Expected,
            "ExpectedWorkflowModelOriginalsServerTraceSourcesItem"
            | "ExpectedWorkflowModelOriginalsClientTraceSourcesItem",
            None,
            "alias",
        ) => Define(ExpectedTrace),
        (
            Operand::Expected,
            "ExpectedWorkflowModelOriginalsServerQualificationBlockedObligationsItem"
            | "ExpectedWorkflowModelOriginalsClientQualificationBlockedObligationsItem",
            None,
            "id",
        ) => Define(ExpectedObligation),
        (
            Operand::Expected,
            "ExpectedBinding",
            Some("discovered-server-selection" | "retained-model-from-attempt"),
            "alias",
        ) => Define(ExpectedBinding),
        (Operand::Expected, "ExpectedBinding", Some("literal-client-input"), "alias") => {
            Define(ObservedConnection)
        }
        (Operand::Expected, "ExpectedClientCheck" | "ExpectedServerCheck", Some(_), "id") => {
            Define(ExpectedCheck)
        }
        (Operand::Expected, "ExpectedEntry", Some("directory" | "file"), "entry") => {
            LocalDefine(ExpectedEntry)
        }
        (Operand::Expected, "LockActor", Some("capture" | "cooperating-writer"), "alias") => {
            LocalDefine(ExpectedLockActor)
        }
        (Operand::Expected, "LockEventRef", Some(_), "actor") => LocalReference(ExpectedLockActor),
        (Operand::Expected, "ExpectedTraceEvent", Some("work-started"), "work") => {
            LocalDefine(ExpectedWork)
        }
        (
            Operand::Expected,
            "ExpectedTraceEvent",
            Some("prepared-core-result" | "work-exited"),
            "work",
        ) => LocalReference(ExpectedWork),
        (
            Operand::Expected,
            "ExpectedBinding",
            Some("discovered-server-selection"),
            "connection",
        )
        | (Operand::Expected, "ExchangeRef", None, "connection")
        | (
            Operand::Expected,
            "ExpectedServerCheck",
            Some("checkpoint-counts" | "capture-lifecycle" | "offer" | "producer-message-boundary"),
            "connection",
        ) => Reference(Connection),
        (Operand::Expected, "ExpectedBinding", Some("discovered-server-selection"), "provider")
        | (Operand::Expected, "ExpectedOffer", Some("held" | "revoked" | "replaced"), "provider") => {
            Reference(Provider)
        }
        (Operand::Expected, "ExpectedBinding", Some("discovered-server-selection"), "project") => {
            Reference(ProviderProject)
        }
        (Operand::Expected, "ExpectedBinding", Some("retained-model-from-attempt"), "attempt") => {
            Reference(OpeningAttempt)
        }
        (Operand::Expected, "ExpectedBinding", Some("retained-model-from-attempt"), "model") => {
            Reference(Model)
        }
        (
            Operand::Expected,
            "ExpectedCleanup",
            Some("release-confirmed" | "own-connection-closed"),
            "connection",
        )
        | (
            Operand::Expected,
            "ExpectedClientCheckConnectedInventoryRefusalCleanup",
            None,
            "connection",
        ) => Reference(ObservedConnection),
        (
            Operand::Expected,
            "ExpectedCleanup",
            Some("release-confirmed" | "own-connection-closed"),
            "attempt",
        ) => Reference(OpeningAttempt),
        (Operand::Expected, "ExpectedCleanup", Some("release-confirmed"), "capture")
        | (
            Operand::Expected,
            "ExpectedCleanupOwnConnectionClosedCapture",
            Some("known"),
            "capture",
        ) => Meaning::ObservationClaim {
            role: ObservedCapture,
            scope: ObservationScope::OpeningAttempt,
        },
        (Operand::Expected, "ExpectedClientCheck", Some("port-trace"), "expectedTrace") => {
            Reference(ExpectedTrace)
        }
        (
            Operand::Expected,
            "ExpectedClientCheck",
            Some(
                "verified-owner"
                | "core-result"
                | "native-open-release-order"
                | "connected-transcript"
                | "connected-opening-transfer"
                | "connected-inventory-refusal"
                | "connected-originals-retained",
            ),
            "attempt",
        )
        | (Operand::Expected, "ExpectedCurrentOpening", Some("attempt"), "attempt") => {
            Reference(OpeningAttempt)
        }
        (
            Operand::Expected,
            "ExpectedClientCheck",
            Some(
                "verified-owner"
                | "download"
                | "archive"
                | "rich-owner"
                | "execution-receipt"
                | "native-open-release-order"
                | "connected-opening-transfer"
                | "connected-originals-retained",
            ),
            "model",
        )
        | (Operand::Expected, "ExecutionOwner", Some("retained"), "model")
        | (
            Operand::Expected,
            "ExpectedClientCheckLocalExplorerStateCurrent",
            Some("model"),
            "model",
        )
        | (
            Operand::Expected,
            "ExpectedClientCheckLocalExplorerStateInspection",
            Some("actual-inspection-result"),
            "model",
        )
        | (
            Operand::Expected,
            "ExpectedClientCheckLocalEvaluationStateResult",
            Some("actual-core-result"),
            "model",
        )
        | (
            Operand::Expected,
            "ExpectedClientCheckNativeWorkspaceOwnerStateModelAuthority",
            Some("actual-retained-owner"),
            "model",
        )
        | (Operand::Expected, "ExpectedCurrentModel", Some("model"), "model")
        | (Operand::Expected, "ExpectedModelBinding", Some("retained-owner"), "model")
        | (Operand::Expected, "TypedAdoption", Some("adopted"), "model")
        | (
            Operand::Expected,
            "ExpectedWorkflowModelOriginalsServerOutcome"
            | "ExpectedWorkflowModelOriginalsClientOutcome",
            Some("intentionally-retained-uncertain"),
            "model",
        ) => Reference(Model),
        (Operand::Expected, "ExpectedClientCheck", Some("model-output-cleared"), "formerModel")
        | (
            Operand::Expected,
            "ExpectedClientCheck",
            Some("navigation"),
            "inspectionOwner" | "outputOwner" | "searchOwner",
        ) => Reference(Model),
        (Operand::Expected, "ExecutionOwner", Some("retained"), "execution")
        | (Operand::Expected, "ExpectedClientCheck", Some("execution-receipt"), "execution")
        | (
            Operand::Expected,
            "ExpectedWorkflowModelOriginalsServerOutcome"
            | "ExpectedWorkflowModelOriginalsClientOutcome",
            Some("intentionally-retained-uncertain"),
            "execution",
        ) => Reference(Execution),
        (
            Operand::Expected,
            "ExpectedClientCheck",
            Some(
                "native-transcript" | "native-open-release-order" | "native-workspace-owner-state",
            ),
            "runtime",
        ) => Reference(NativeRuntime),
        (
            Operand::Expected,
            "ExpectedClientCheck",
            Some(
                "connected-transcript"
                | "connected-opening-transfer"
                | "connected-inventory-refusal"
                | "connected-originals-retained",
            ),
            "pending",
        ) => Reference(PendingConnectedOpening),
        (
            Operand::Expected,
            "ExpectedClientCheck",
            Some(
                "owner-absent"
                | "verified-owner"
                | "current-opening"
                | "current-model"
                | "navigation"
                | "capture-cleanup"
                | "execution-owner"
                | "local-explorer-state"
                | "local-evaluation-state"
                | "model-output-cleared"
                | "native-workspace-owner-state"
                | "connected-inventory-refusal",
            ),
            "checkpoint",
        )
        | (
            Operand::Expected,
            "ExpectedClientCheck",
            Some("native-open-release-order" | "connected-opening-transfer"),
            "beforeInspectionCheckpoint" | "publicationCheckpoint",
        )
        | (
            Operand::Expected,
            "ExpectedClientCheck",
            Some("connected-originals-retained"),
            "publicationCheckpoint",
        )
        | (
            Operand::Expected,
            "ExpectedServerCheck",
            Some(
                "rpc-refusal"
                | "checkpoint-counts"
                | "capture-lifecycle"
                | "offer"
                | "capture-unavailable",
            ),
            "checkpoint",
        )
        | (
            Operand::Expected,
            "ExpectedWorkflowModelOriginalsServerOutcome"
            | "ExpectedWorkflowModelOriginalsClientOutcome",
            Some("clean" | "intentionally-retained-uncertain"),
            "finalCheckpoint",
        ) => Reference(Checkpoint),
        (
            Operand::Expected,
            "ExpectedServerCheck",
            Some("capture" | "inventory" | "stream" | "release"),
            "capture",
        )
        | (Operand::Expected, "ExpectedLifecycleState", Some("ready" | "released"), "capture") => {
            Reference(Capture)
        }
        (
            Operand::Expected,
            "ExpectedServerCheck",
            Some("capture" | "workspace-snapshot" | "capture-unavailable" | "legacy-open-selected"),
            "binding",
        )
        | (Operand::Expected, "ExpectedServerCheckCooperatingLockOrderScope", None, "binding") => {
            Reference(ExpectedBinding)
        }
        (Operand::Expected, "ExpectedServerCheck", Some("producer-message-boundary"), "probe") => {
            Reference(MessageProbe)
        }
        (
            Operand::Expected,
            "ExpectedLifecycleState",
            Some("capturing" | "prepared-private"),
            "attempt",
        )
        | (Operand::Expected, "LockActor", Some("capture"), "attempt") => Reference(CaptureAttempt),
        (Operand::Expected, "LockActor", Some("capture"), "pending") => Reference(PendingCapture),
        (Operand::Expected, "LockActor", Some("cooperating-writer"), "writer") => Reference(Writer),
        (
            Operand::Expected,
            "ExpectedLifecycleState",
            Some("capturing" | "prepared-private"),
            "work",
        )
        | (Operand::Expected, "ExpectedLifecycleState", Some("closed"), "stillOwnedWork") => {
            Meaning::ObservationClaim {
                role: ObservedWork,
                scope: ObservationScope::CaptureAttempt,
            }
        }
        (Operand::Expected, "ExpectedOffer", Some("held" | "revoked"), "registration")
        | (Operand::Expected, "ExpectedOffer", Some("replaced"), "current" | "previous") => {
            Meaning::ObservationClaim {
                role: ObservedRegistration,
                scope: ObservationScope::ConnectionProvider,
            }
        }
        (Operand::Expected, "PickerSignal", Some("file-selection"), "file") => Reference(File),
        (
            Operand::Expected,
            "ExpectedLineageTreatment",
            Some("compared" | "compared-by-decision"),
            "checkIds",
        )
        | (
            Operand::Expected,
            "ExpectedLineageTreatment",
            Some("superseded-authoring-error"),
            "replacementCheckIds",
        ) => Reference(ExpectedCheck),
        (Operand::Expected, "ExpectedLineageTreatment", Some("unresolved"), "obligation") => {
            Reference(ExpectedObligation)
        }
        (
            Operand::Expected,
            "ExpectedCoreProjection",
            Some("conceptual-specification"),
            "originalOwner",
        ) => Blocked(SemanticBlocker::ConceptualOriginalOwner),
        (
            Operand::Expected,
            "ExpectedClientCheck",
            Some("rich-owner"),
            "expectedProvenanceRich",
        )
        | (
            Operand::Expected,
            "ExpectedClientCheckRichOwnerGraph",
            Some("retained"),
            "expectedRich",
        )
        | (
            Operand::Expected,
            "ExpectedCoreProjectionInspectRetainedRich",
            Some("retained"),
            "expectedRich",
        )
        | (
            Operand::Expected,
            "ExpectedCoreProjection",
            Some("conceptual-specification"),
            "expectedGraph",
        ) => Reference(ExpectedRich),
        (
            Operand::Expected,
            "ExpectedClientCheckConnectedTranscriptManifest"
            | "ExpectedClientCheckConnectedOpeningTransferOriginRecord"
            | "ExpectedClientCheckConnectedInventoryRefusalManifest"
            | "ExpectedClientCheckConnectedOriginalsRetainedOriginRecord"
            | "ExpectedServerCheckCapturePrivateRecord",
            None,
            "expectedBytes",
        )
        | (Operand::Expected, "ExpectedClientCheck", Some("download"), "expectedBytes")
        | (
            Operand::Expected,
            "ExpectedClientCheck",
            Some("native-open-release-order"),
            "sourceBytes",
        )
        | (Operand::Expected, "ExpectedCoreProjection", Some("inspect"), "expectedSemanticBytes")
        | (Operand::Expected, "ExpectedEntries", Some("file-series"), "expectedBytes")
        | (
            Operand::Expected,
            "ExpectedEntry" | "ExpectedOriginalOwner",
            Some("file"),
            "expectedBytes",
        )
        | (
            Operand::Expected,
            "ExpectedPortReply",
            Some("exact-bytes" | "picker-selected"),
            "expectedBytes",
        )
        | (
            Operand::Expected,
            "ExpectedProjectionAvailableContent" | "ExpectedServerCheckLegacyOpenSelectedContent",
            Some("exact-bytes" | "semantic-json"),
            "expectedBytes",
        )
        | (
            Operand::Expected,
            "ExpectedRichScalar" | "ExpectedRichValueValue",
            Some("unknown-symbol"),
            "sourceBytes",
        )
        | (
            Operand::Expected,
            "ExpectedRichScalar" | "ExpectedRichValueValue",
            Some("blob" | "clob"),
            "expectedBytes",
        )
        | (
            Operand::Expected,
            "ExpectedServerCheck",
            Some("stream" | "producer-message-boundary"),
            "expectedBytes",
        )
        | (
            Operand::Expected,
            "ExpectedWorkflowModelOriginalsServerRichSourcesItem"
            | "ExpectedWorkflowModelOriginalsClientRichSourcesItem",
            None,
            "sourceBytes",
        ) => Reference(ExpectedBytes),
        _ => Blocked(SemanticBlocker::UnclassifiedSite(site)),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cleanup_capture_is_an_observation_claim_requiring_actual_attempt_binding() {
        let site = Site::test(
            Operand::Expected,
            "ExpectedCleanup",
            Some("release-confirmed"),
            "capture",
        );
        assert_eq!(
            classify(site),
            Meaning::ObservationClaim {
                role: Role::ObservedCapture,
                scope: ObservationScope::OpeningAttempt,
            }
        );
    }
}

#[cfg(test)]
#[path = "source_sites_tests.rs"]
mod source_sites_tests;
