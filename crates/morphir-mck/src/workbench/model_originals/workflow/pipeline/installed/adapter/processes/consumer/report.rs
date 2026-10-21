//! Closed report DATA borrowed from the actual retained terminal owner.
use super::*;
use crate::workbench::model_originals::workflow::{
    UniqueKey, installed_measurements as measurements,
};
use serde::{
    Serialize, Serializer,
    ser::{SerializeMap, SerializeSeq},
};

#[derive(Debug, Serialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub(super) enum LaunchData {
    Unobserved,
    NodePackage {
        runtime: measurements::implementation::OsOperand,
        entry: measurements::implementation::OsOperand,
        helper: measurements::implementation::OsOperand,
        directory: measurements::implementation::OsOperand,
    },
    NativeExecutable {
        program: measurements::implementation::OsOperand,
        runtime: measurements::implementation::OsOperand,
        helper: measurements::implementation::OsOperand,
        directory: measurements::implementation::OsOperand,
    },
}
#[cfg(target_os = "macos")]
impl LaunchData {
    pub(super) fn prepare(
        run: &mut InstalledClientRun<'_>,
        binding: &binding::ConsumerBinding,
        process: &ProcessDescription,
    ) -> Result<Self, InstalledAdapterError> {
        let binding::ConsumerBinding::Observed(binding) = binding else {
            return Ok(Self::Unobserved);
        };
        let (runtime, helper, directory) = match binding {
            binding::ObservedLaunch::NodePackage {
                runtime,
                helper,
                directory,
            }
            | binding::ObservedLaunch::NativeExecutable {
                runtime,
                helper,
                directory,
            } => (runtime, helper, directory),
        };
        let runtime = run.observation_operand(runtime)?;
        let helper = run.observation_operand(helper)?;
        let directory = run.observation_operand(directory)?;
        Ok(match binding {
            binding::ObservedLaunch::NodePackage { .. } => Self::NodePackage {
                runtime,
                helper,
                directory,
                entry: run.observation_operand(
                    process
                        .arguments
                        .first()
                        .ok_or(InstalledAdapterError::ObservationIncomplete)?,
                )?,
            },
            binding::ObservedLaunch::NativeExecutable { .. } => Self::NativeExecutable {
                runtime,
                helper,
                directory,
                program: run.observation_operand(&process.program)?,
            },
        })
    }
}
#[derive(Serialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub(super) enum TerminalData {
    NoFrame,
    HeaderPrefix { bytes: usize },
    BodyPrefix { expected: usize, bytes: usize },
    Receiving,
    CloseRetained,
    CloseAckWritten,
    Drained,
    Unused,
}
impl Serialize for wire::ConsumerFailureKind {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(self.code())
    }
}
impl Serialize for record::ConsumerAckDelivery {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(None)?;
        match self {
            Self::NotIssued => m.serialize_entry("kind", "not-issued")?,
            Self::Prefix { written, total } => {
                m.serialize_entry("kind", "prefix")?;
                m.serialize_entry("written", written)?;
                m.serialize_entry("total", total)?;
            }
            Self::Written { total } => {
                m.serialize_entry("kind", "written")?;
                m.serialize_entry("total", total)?;
            }
        }
        m.end()
    }
}
struct Completion<'a>(&'a record::ConsumerOperationRecord);
impl Serialize for Completion<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(None)?;
        match self.0.completion {
            record::ConsumerRecordCompletion::Drained => m.serialize_entry("kind", "drained")?,
            record::ConsumerRecordCompletion::Interrupted => {
                m.serialize_entry("kind", "interrupted")?;
                m.serialize_entry("firstFailure", &self.0.first_failure)?;
            }
        }
        m.end()
    }
}
#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Association<'a> {
    process_ordinal: u64,
    action_index: usize,
    command: &'static str,
    launch: &'a LaunchData,
}
struct Decimal(u64);
impl std::fmt::Display for Decimal {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Display::fmt(&self.0, f)
    }
}
impl Serialize for Decimal {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(self)
    }
}
#[cfg(target_os = "macos")]
struct Clock<'a>(&'a ConsumerPortControl);
#[cfg(target_os = "macos")]
impl Serialize for Clock<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(None)?;
        if let Some(Ok(clock)) = self.0.deadline.get() {
            m.serialize_entry("kind", "issued")?;
            m.serialize_entry("domain", "darwin-mach-continuous-nanoseconds")?;
            m.serialize_entry("version", wire::VERSION)?;
            m.serialize_entry("calibratedAtNs", &Decimal(clock.calibrated_at_ns()))?;
            m.serialize_entry("endNs", &Decimal(clock.end_ns()))?;
            m.serialize_entry("timebaseNumer", &clock.timebase().numerator())?;
            m.serialize_entry("timebaseDenom", &clock.timebase().denominator())?;
        } else {
            m.serialize_entry("kind", "unissued")?;
        }
        m.end()
    }
}
struct Frames<'a>(&'a [wire::DecodedConsumerEnvelope]);
impl Serialize for Frames<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut seq = s.serialize_seq(Some(self.0.len()))?;
        for row in self.0 {
            seq.serialize_element(&FrameRow(row))?;
        }
        seq.end()
    }
}
struct FrameRow<'a>(&'a wire::DecodedConsumerEnvelope);
impl Serialize for FrameRow<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(2))?;
        m.serialize_entry("literal", &self.0.literal)?;
        m.serialize_entry("delivery", &self.0.delivery)?;
        m.end()
    }
}
#[cfg(target_os = "macos")]
struct Endpoint<'a> {
    role: &'static str,
    channel: &'a collector::Channel,
    frames: &'a [wire::DecodedConsumerEnvelope],
}
#[cfg(target_os = "macos")]
impl Serialize for Endpoint<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(4))?;
        let (terminal, fault) = self.channel.record_terminal(self.frames);
        m.serialize_entry("role", self.role)?;
        m.serialize_entry("terminal", &terminal)?;
        m.serialize_entry("fault", &fault)?;
        m.serialize_entry("frames", &Frames(self.frames))?;
        m.end()
    }
}
#[cfg(target_os = "macos")]
impl Serialize for record::ConsumerOperationRecord {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let action_index = self.reservation.action_index;
        let mut m = s.serialize_map(Some(6))?;
        m.serialize_entry("kind", "recorded")?;
        m.serialize_entry("version", wire::VERSION)?;
        m.serialize_entry(
            "association",
            &Association {
                process_ordinal: self.finished.description.ordinal,
                action_index,
                command: "publish",
                launch: &self.reservation.launch,
            },
        )?;
        m.serialize_entry("clock", &Clock(&self.ports.control))?;
        m.serialize_entry("completion", &Completion(self))?;
        m.serialize_entry(
            "endpoints",
            &[
                Endpoint {
                    role: "outer",
                    channel: &self.ports.channels[0],
                    frames: &self.frames[0],
                },
                Endpoint {
                    role: "transfer-helper",
                    channel: &self.ports.channels[1],
                    frames: &self.frames[1],
                },
            ],
        )?;
        m.end()
    }
}
#[cfg(not(target_os = "macos"))]
impl Serialize for record::ConsumerOperationRecord {
    fn serialize<S: Serializer>(&self, _s: S) -> Result<S::Ok, S::Error> {
        unreachable!("unsupported targets cannot issue a live consumer record")
    }
}
#[derive(Clone, Copy)]
pub(in crate::workbench::model_originals::workflow) enum FactKind {
    Release,
    Commit,
    Cleanup,
}
impl FactKind {
    fn matches(self, fact: &wire::Fact) -> bool {
        matches!(
            (self, fact),
            (Self::Release, wire::Fact::Release { .. })
                | (Self::Commit, wire::Fact::Commit { .. })
                | (Self::Cleanup, wire::Fact::Cleanup { .. })
        )
    }
}
pub(in crate::workbench::model_originals::workflow) struct DynamicFact<'a> {
    pub(in crate::workbench::model_originals::workflow) record: &'a record::ConsumerOperationRecord,
    pub(in crate::workbench::model_originals::workflow) kind: FactKind,
}
#[derive(Serialize)]
struct FrameRef {
    role: &'static str,
    sequence: u64,
}
impl Serialize for DynamicFact<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        for (index, frames) in self.record.frames.iter().enumerate() {
            for row in frames {
                if let wire::Frame::Fact { fact, .. } = &row.frame {
                    if self.kind.matches(fact) {
                        let mut m = s.serialize_map(None)?;
                        m.serialize_entry("kind", "observed")?;
                        m.serialize_entry(
                            "frameRef",
                            &FrameRef {
                                role: if index == 0 {
                                    "outer"
                                } else {
                                    "transfer-helper"
                                },
                                sequence: row.sequence(),
                            },
                        )?;
                        fact_fields(fact, &mut m)?;
                        return m.end();
                    }
                }
            }
        }
        s.serialize_str("unobserved")
    }
}
pub(super) fn fact_fields<M: SerializeMap>(fact: &wire::Fact, m: &mut M) -> Result<(), M::Error> {
    match fact {
        wire::Fact::Release {
            request,
            capture,
            binding,
            request_sha,
            reply_sha,
        } => {
            m.serialize_entry("requestId", request)?;
            m.serialize_entry("captureId", capture)?;
            m.serialize_entry("binding", binding)?;
            m.serialize_entry("requestSha256", request_sha)?;
            m.serialize_entry("replySha256", reply_sha)?;
        }
        wire::Fact::Commit {
            path,
            policy,
            outcome,
        } => {
            m.serialize_entry("path", path)?;
            m.serialize_entry("policy", policy.key())?;
            m.serialize_entry("outcome", outcome.key())?;
        }
        wire::Fact::Cleanup { path, outcome } => {
            m.serialize_entry("path", path)?;
            m.serialize_entry("outcome", outcome.key())?;
        }
    }
    Ok(())
}
impl<const MAX: usize> Serialize for wire::WireText<MAX> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(&self.0)
    }
}
impl<const EXACT: usize> Serialize for wire::Hex<EXACT> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.serialize_str(self.as_str())
    }
}
impl Serialize for wire::Decimal<false> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        Decimal(self.value()).serialize(s)
    }
}
impl Serialize for wire::Binding {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(4))?;
        m.serialize_entry("sessionId", &self.session)?;
        m.serialize_entry("providerId", &self.provider)?;
        m.serialize_entry("sourceLocator", &self.source)?;
        m.serialize_entry("projectId", &self.project)?;
        m.end()
    }
}
impl Serialize for wire::Operand {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(2))?;
        let Self::UnixBytes { bytes } = self;
        m.serialize_entry("kind", "unix-bytes")?;
        m.serialize_entry("bytes", bytes)?;
        m.end()
    }
}
impl Serialize for wire::LiteralBytes {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(2))?;
        match self {
            Self::Utf8 { text } => {
                m.serialize_entry("kind", "utf8")?;
                m.serialize_entry("text", text)?
            }
            Self::Hex { hex } => {
                m.serialize_entry("kind", "hex")?;
                m.serialize_entry("hex", hex)?
            }
        }
        m.end()
    }
}
