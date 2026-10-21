//! Closed private DATA codec. Parsing never issues a receive or ACK capability.
use super::*;
use crate::json::strict::Document;
use crate::workbench::model_originals::workflow::decode::{
    Decode, DecodeError, Decoder, Fields, Items, UniqueKey, discriminator, string,
};

pub(in crate::workbench::model_originals::workflow) const VERSION: &str =
    crate::workbench::configuration::OperationPortRevision::Draft1.wire();
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow) enum ConsumerCodecError {
    ClockBasis,
    Framing,
    FrameTooLarge,
    Utf8,
    Json,
    Shape,
    Revision,
    Role,
    Direction,
    Association,
    PriorFault,
    Sequence,
    Outstanding,
    Ticket,
    Expired,
    Io(std::io::ErrorKind),
    Resource(InstalledObservationError),
    Decode,
    Deadline(super::deadline::DeadlineError),
}
impl ConsumerCodecError {
    pub(in crate::workbench::model_originals::workflow) fn failure_kind(
        &self,
    ) -> ConsumerFailureKind {
        match self {
            Self::ClockBasis => ConsumerFailureKind::ClockBasis,
            Self::Framing => ConsumerFailureKind::Framing,
            Self::FrameTooLarge => ConsumerFailureKind::FrameTooLarge,
            Self::Utf8 => ConsumerFailureKind::Utf8,
            Self::Json => ConsumerFailureKind::Json,
            Self::Shape => ConsumerFailureKind::Shape,
            Self::Revision => ConsumerFailureKind::Revision,
            Self::Role => ConsumerFailureKind::Role,
            Self::Direction => ConsumerFailureKind::Direction,
            Self::Association => ConsumerFailureKind::Association,
            Self::PriorFault => ConsumerFailureKind::PriorFault,
            Self::Sequence => ConsumerFailureKind::Sequence,
            Self::Outstanding => ConsumerFailureKind::Outstanding,
            Self::Ticket => ConsumerFailureKind::Ticket,
            Self::Expired => ConsumerFailureKind::Expired,
            Self::Io(_) => ConsumerFailureKind::Io,
            Self::Resource(_) => ConsumerFailureKind::Receiving,
            Self::Decode => ConsumerFailureKind::Decode,
            Self::Deadline(_) => ConsumerFailureKind::Deadline,
        }
    }
}
/// Stored failure classification only. This cannot construct an actual I/O,
/// receiving or deadline fault, process owner, invocation or successful fact.
#[derive(Clone, Copy)]
pub(in crate::workbench::model_originals::workflow) enum ConsumerFailureKind {
    ClockBasis,
    Framing,
    FrameTooLarge,
    Utf8,
    Json,
    Shape,
    Revision,
    Role,
    Direction,
    Association,
    PriorFault,
    Sequence,
    Outstanding,
    Ticket,
    Expired,
    Io,
    Receiving,
    Decode,
    Deadline,
}
impl ConsumerFailureKind {
    pub(in crate::workbench::model_originals::workflow) const ALL: [Self; 19] = [
        Self::ClockBasis,
        Self::Framing,
        Self::FrameTooLarge,
        Self::Utf8,
        Self::Json,
        Self::Shape,
        Self::Revision,
        Self::Role,
        Self::Direction,
        Self::Association,
        Self::PriorFault,
        Self::Sequence,
        Self::Outstanding,
        Self::Ticket,
        Self::Expired,
        Self::Io,
        Self::Receiving,
        Self::Decode,
        Self::Deadline,
    ];
    pub(in crate::workbench::model_originals::workflow) fn code(self) -> &'static str {
        match self {
            Self::ClockBasis => "clock-basis",
            Self::Framing => "framing",
            Self::FrameTooLarge => "frame-too-large",
            Self::Utf8 => "utf8",
            Self::Json => "json",
            Self::Shape => "shape",
            Self::Revision => "revision",
            Self::Role => "role",
            Self::Direction => "direction",
            Self::Association => "association",
            Self::PriorFault => "prior-fault",
            Self::Sequence => "sequence",
            Self::Outstanding => "outstanding",
            Self::Ticket => "ticket",
            Self::Expired => "expired",
            Self::Io => "io",
            Self::Receiving => "receiving",
            Self::Decode => "decode",
            Self::Deadline => "deadline",
        }
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow) enum ConsumerEnvelopeKind {
    Open,
    Fact,
    HelperStarted,
    Close,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConsumerAckProgress {
    Pending,
    Complete,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConsumerDrainProgress {
    Pending,
    Complete,
}
pub enum ConsumerReceiveProgress {
    Pending,
    AwaitingAssociation,
    Unused,
    Retained(ConsumerPendingAck),
}
pub struct ConsumerPendingAck {
    pub(super) _private: (),
    #[cfg(target_os = "macos")]
    pub(super) control: std::sync::Weak<ConsumerPortControl>,
    #[cfg(target_os = "macos")]
    pub(super) role: ConsumerProducerRole,
    #[cfg(target_os = "macos")]
    pub(super) sequence: u64,
    #[cfg(target_os = "macos")]
    pub(super) cache_index: usize,
    #[cfg(target_os = "macos")]
    pub(super) bytes: [u8; 128],
    #[cfg(target_os = "macos")]
    pub(super) length: usize,
    #[cfg(target_os = "macos")]
    pub(super) cursor: usize,
}
#[cfg(all(test, target_os = "macos"))]
impl ConsumerPendingAck {
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn test_written_prefix(
        &self,
    ) -> usize {
        self.cursor
    }
}
impl std::fmt::Debug for ConsumerPendingAck {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ConsumerPendingAck")
    }
}
impl std::fmt::Debug for ConsumerReceiveProgress {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Pending => f.write_str("Pending"),
            Self::AwaitingAssociation => f.write_str("AwaitingAssociation"),
            Self::Unused => f.write_str("Unused"),
            Self::Retained(_) => f.write_str("Retained"),
        }
    }
}
pub(in crate::workbench::model_originals::workflow) struct DecodedConsumerEnvelope {
    pub(super) frame: Frame,
    pub(super) literal: String,
    #[cfg(target_os = "macos")]
    pub(super) delivery: super::record::ConsumerAckDelivery,
}
impl DecodedConsumerEnvelope {
    #[cfg(all(test, target_os = "macos"))]
    pub(in crate::workbench::model_originals::workflow) fn delivery(
        &self,
    ) -> super::record::ConsumerAckDelivery {
        self.delivery
    }
    pub(in crate::workbench::model_originals::workflow) fn kind(&self) -> ConsumerEnvelopeKind {
        match self.frame {
            Frame::Open { .. } => ConsumerEnvelopeKind::Open,
            Frame::Fact { .. } => ConsumerEnvelopeKind::Fact,
            Frame::HelperStarted { .. } => ConsumerEnvelopeKind::HelperStarted,
            Frame::Close { .. } => ConsumerEnvelopeKind::Close,
        }
    }
    pub(in crate::workbench::model_originals::workflow) fn sequence(&self) -> u64 {
        self.frame.sequence()
    }
    pub(in crate::workbench::model_originals::workflow) fn literal_utf8(&self) -> &str {
        &self.literal
    }
}
pub(in crate::workbench::model_originals::workflow) struct DecodedRetained {
    pub(super) sequence: u64,
    pub(super) literal: String,
}
impl DecodedRetained {
    pub(in crate::workbench::model_originals::workflow) fn sequence(&self) -> u64 {
        self.sequence
    }
    pub(in crate::workbench::model_originals::workflow) fn literal_utf8(&self) -> &str {
        &self.literal
    }
}
#[derive(Debug)]
pub(super) struct Count(pub(super) u64);
impl Decode for Count {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        owner.ready()?;
        let Document::Number(number) = value else {
            return Err(DecodeError::Shape("canonical count"));
        };
        let token = number.as_str();
        owner.bytes(token.len().saturating_mul(2))?;
        if token.is_empty()
            || !token.bytes().all(|b| b.is_ascii_digit())
            || (token.len() > 1 && token.starts_with('0'))
        {
            return Err(DecodeError::Shape("canonical count"));
        }
        token
            .parse()
            .map(Self)
            .map_err(|_| DecodeError::Shape("count range"))
    }
}
#[derive(Debug)]
pub(super) struct Decimal<const SIGNED: bool>(i128);
impl<const SIGNED: bool> Decode for Decimal<SIGNED> {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        owner.bytes(text.len())?;
        let digits = if SIGNED {
            text.strip_prefix('-').unwrap_or(text)
        } else {
            text
        };
        if digits.is_empty()
            || !digits.bytes().all(|b| b.is_ascii_digit())
            || (digits.len() > 1 && digits.starts_with('0'))
            || text == "-0"
        {
            return Err(DecodeError::Shape("canonical decimal"));
        }
        let value = if SIGNED {
            i128::from(
                text.parse::<i32>()
                    .map_err(|_| DecodeError::Shape("i32 range"))?,
            )
        } else {
            i128::from(
                text.parse::<u64>()
                    .map_err(|_| DecodeError::Shape("u64 range"))?,
            )
        };
        Ok(Self(value))
    }
}
impl Decimal<false> {
    fn value(&self) -> u64 {
        self.0 as u64
    }
}
#[derive(Debug)]
pub(super) struct WireText<const MAX: usize>(pub(super) String);
impl<const MAX: usize> Decode for WireText<MAX> {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        if text.len() > MAX {
            return Err(DecodeError::Shape("UTF8 byte limit"));
        }
        owner.bytes(text.len())?;
        Ok(Self(text.to_owned()))
    }
}
#[derive(Debug)]
pub(super) struct Hex<const EXACT: usize>(String);
impl<const EXACT: usize> Decode for Hex<EXACT> {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        owner.bytes(text.len())?;
        if text.len() % 2 != 0
            || (EXACT != 0 && text.len() != EXACT)
            || !text
                .bytes()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        {
            return Err(DecodeError::Shape("literal lowercase hex"));
        }
        Ok(Self(text.to_owned()))
    }
}
tagged! { LiteralBytes("kind") {Utf8=>"utf8"{text:WireText<131072> =>"text"},Hex=>"hex"{hex:Hex<0> =>"hex"}} }
tagged! { Operand("kind") {UnixBytes=>"unix-bytes"{bytes:LiteralBytes=>"bytes"}} }
impl Operand {
    #[cfg(unix)]
    pub(super) fn absolute(&self, owner: &mut Decoder) -> Result<bool, DecodeError> {
        match self {
            Self::UnixBytes {
                bytes: LiteralBytes::Utf8 { text },
            } => {
                owner.bytes(text.0.len())?;
                Ok(std::path::Path::new(&text.0).is_absolute())
            }
            Self::UnixBytes {
                bytes: LiteralBytes::Hex { hex },
            } => {
                owner.bytes(hex.0.len())?;
                Ok(hex.0.starts_with("2f"))
            }
        }
    }
    #[cfg(unix)]
    pub(super) fn matches(&self, actual: &OsStr, owner: &mut Decoder) -> Result<bool, DecodeError> {
        use std::os::unix::ffi::OsStrExt;
        let Self::UnixBytes { bytes } = self;
        let actual = actual.as_bytes();
        match bytes {
            LiteralBytes::Utf8 { text } => {
                owner.bytes(text.0.len().saturating_add(actual.len()))?;
                Ok(text.0.as_bytes() == actual)
            }
            LiteralBytes::Hex { hex } => {
                owner.bytes(hex.0.len().saturating_add(actual.len()))?;
                if hex.0.len() / 2 != actual.len() {
                    return Ok(false);
                };
                Ok(hex
                    .0
                    .as_bytes()
                    .as_chunks::<2>()
                    .0
                    .iter()
                    .zip(actual)
                    .all(|(pair, b)| {
                        let digit = |x: u8| if x <= b'9' { x - b'0' } else { x - b'a' + 10 };
                        digit(pair[0]) * 16 + digit(pair[1]) == *b
                    }))
            }
        }
    }
    #[cfg(not(unix))]
    pub(super) fn matches(
        &self,
        _actual: &OsStr,
        owner: &mut Decoder,
    ) -> Result<bool, DecodeError> {
        owner.ready()?;
        Ok(false)
    }
}
record! { Binding {session:WireText<128> =>"sessionId",provider:WireText<128> =>"providerId",source:WireText<4096> =>"sourceLocator",project:WireText<12288> =>"projectId"} }
words! {Outcome {Returned=>"returned",Raised=>"raised"}}
words! {Create {Create=>"create"}}
tagged! {Fact("kind") {
 Release=>"release-accepted"{request:Decimal<false> =>"requestId",capture:WireText<128> =>"captureId",binding:Binding=>"binding",request_sha:Hex<64> =>"requestSha256",reply_sha:Hex<64> =>"replySha256"},
 Commit=>"destination-commit-finished"{path:Operand=>"path",policy:Create=>"policy",outcome:Outcome=>"outcome"},
 Cleanup=>"scratch-cleanup-finished"{path:Operand=>"path",outcome:Outcome=>"outcome"}
} }
record! {Launch {program:Operand=>"program",arguments:Items<Operand,0,131072> =>"arguments",directory:Operand=>"directory"}}
words! {Operation {Seek=>"seek",Size=>"size",Read=>"read"}}
words! {NotReadReason {Wait=>"wait-incomplete",Refused=>"size-refused",Size=>"size-failed",Seek=>"seek-failed"}}
tagged! {ReadError("kind") {Errno=>"errno"{code:Decimal<false> =>"code"},Unavailable=>"unavailable"{}}}
tagged! {OutputRead("kind") {Complete=>"complete"{length:Decimal<false> =>"byteLength"},Short=>"short-read"{length:Decimal<false> =>"byteLength"},NotRead=>"not-read"{reason:NotReadReason=>"reason"},Failed=>"failed"{operation:Operation=>"operation",length:Decimal<false> =>"byteLength",error:ReadError=>"error"}}}
words! {CloseOperation {Close=>"close"}}
tagged! {Disposal("kind"){Disposed=>"disposed"{},Failed=>"failed"{operation:CloseOperation=>"operation",code:Decimal<false> =>"errorCode"}}}
tagged! {Output("kind"){NotCreated=>"not-created"{},Owned=>"owned"{read:OutputRead=>"read",disposal:Disposal=>"disposal"}}}
tagged! {Wait("kind"){Waited=>"waited"{status:Decimal<true> =>"rawStatus"},Failed=>"failed"{code:Decimal<false> =>"errorCode"}}}
words! {LaunchStage{Preparation=>"preparation",Fork=>"fork"}}
tagged! {HelperCompletion("kind"){
 NotApplicable=>"not-applicable"{},InProcess=>"in-process"{},NotAttempted=>"not-attempted"{},
 LaunchFailed=>"launch-failed"{stage:LaunchStage=>"stage",stdout:Output=>"stdout",stderr:Output=>"stderr"},
 Started=>"started"{wait:Wait=>"wait",stdout:Output=>"stdout",stderr:Output=>"stderr"}
}}
tagged! {Frame("kind"){
 Open=>"open"{version:WireText<64> =>"version",sequence:Count=>"sequence"},
 Fact=>"fact"{version:WireText<64> =>"version",sequence:Count=>"sequence",fact:Fact=>"fact"},
 HelperStarted=>"helper-started"{version:WireText<64> =>"version",sequence:Count=>"sequence",launch:Launch=>"launch"},
 Close=>"close"{version:WireText<64> =>"version",sequence:Count=>"sequence",attempted:Count=>"attemptedHooks",started:Count=>"startedFactFrames",retained:Count=>"retainedBusinessFacts",helper:HelperCompletion=>"helper"}
}}
record! {Retained{kind:WireText<16> =>"kind",version:WireText<64> =>"version",sequence:Count=>"sequence"}}
impl Frame {
    pub(super) fn validate_business_prefix(
        &self,
        previous: &[DecodedConsumerEnvelope],
    ) -> Result<(), ConsumerCodecError> {
        let mut acknowledged = 0u64;
        for envelope in previous {
            if let Self::Fact { fact: prior, .. } = &envelope.frame {
                acknowledged = acknowledged
                    .checked_add(1)
                    .ok_or(ConsumerCodecError::Shape)?;
                if let Self::Fact { fact, .. } = self
                    && matches!(
                        (fact, prior),
                        (Fact::Release { .. }, Fact::Release { .. })
                            | (Fact::Commit { .. }, Fact::Commit { .. })
                            | (Fact::Cleanup { .. }, Fact::Cleanup { .. })
                    )
                {
                    return Err(ConsumerCodecError::Sequence);
                }
            }
        }
        if let Self::Close {
            attempted,
            started,
            retained,
            ..
        } = self
            && (attempted.0 != acknowledged
                || started.0 != acknowledged
                || retained.0 != acknowledged)
        {
            return Err(ConsumerCodecError::Shape);
        }
        Ok(())
    }
    pub(super) fn sequence(&self) -> u64 {
        match self {
            Self::Open { sequence, .. }
            | Self::Fact { sequence, .. }
            | Self::HelperStarted { sequence, .. }
            | Self::Close { sequence, .. } => sequence.0,
        }
    }
    fn version(&self) -> &str {
        match self {
            Self::Open { version, .. }
            | Self::Fact { version, .. }
            | Self::HelperStarted { version, .. }
            | Self::Close { version, .. } => &version.0,
        }
    }
    pub(super) fn validate(
        &self,
        role: ConsumerProducerRole,
        owner: &mut Decoder,
    ) -> Result<(), ConsumerCodecError> {
        // Exact equality to the sole supported library-validated draft. This
        // is not another SemVer parser and allocates no version scratch.
        owner
            .bytes(self.version().len().saturating_add(VERSION.len()))
            .map_err(|_| ConsumerCodecError::Decode)?;
        if self.version() != VERSION {
            return Err(ConsumerCodecError::Revision);
        }
        match self {
            Self::Fact { fact, .. } => match (fact, role) {
                (Fact::Release { .. }, ConsumerProducerRole::TransferHelper)
                | (Fact::Commit { .. } | Fact::Cleanup { .. }, ConsumerProducerRole::Outer) => {}
                _ => return Err(ConsumerCodecError::Role),
            },
            Self::HelperStarted { .. } if role != ConsumerProducerRole::Outer => {
                return Err(ConsumerCodecError::Role);
            }
            Self::Close {
                attempted,
                started,
                retained,
                helper,
                ..
            } => {
                if role == ConsumerProducerRole::TransferHelper
                    && !matches!(helper, HelperCompletion::NotApplicable { .. })
                {
                    return Err(ConsumerCodecError::Role);
                }
                let max = if role == ConsumerProducerRole::Outer {
                    2
                } else {
                    1
                };
                if attempted.0 > max || started.0 > attempted.0 || retained.0 > started.0 {
                    return Err(ConsumerCodecError::Shape);
                }
                match helper {
                    HelperCompletion::LaunchFailed { stdout, stderr, .. }
                    | HelperCompletion::Started { stdout, stderr, .. } => {
                        validate_output(stdout)?;
                        validate_output(stderr)?
                    }
                    _ => {}
                }
                if let HelperCompletion::Started {
                    wait: Wait::Failed { code },
                    ..
                } = helper
                {
                    positive(code)?
                }
            }
            _ => {}
        };
        Ok(())
    }
}
fn positive(value: &Decimal<false>) -> Result<(), ConsumerCodecError> {
    if value.value() == 0 || value.value() > i32::MAX as u64 {
        Err(ConsumerCodecError::Shape)
    } else {
        Ok(())
    }
}
fn validate_output(output: &Output) -> Result<(), ConsumerCodecError> {
    if let Output::Owned { read, disposal } = output {
        if let OutputRead::Failed {
            operation,
            length,
            error,
        } = read
        {
            if !matches!(operation, Operation::Read) && length.value() != 0 {
                return Err(ConsumerCodecError::Shape);
            }
            if let ReadError::Errno { code } = error {
                positive(code)?
            }
        }
        if let Disposal::Failed { code, .. } = disposal {
            positive(code)?
        }
    }
    Ok(())
}
