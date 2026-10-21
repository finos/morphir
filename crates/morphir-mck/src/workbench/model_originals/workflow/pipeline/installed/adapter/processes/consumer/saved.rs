//! Strict private report DATA. Nothing here constructs a live process or port.
use super::*;
use crate::json::strict::Document;
use crate::workbench::model_originals::workflow::{
    Decode, DecodeError, Decoder, Fields, Items, Literal, Natural, Nullable, Text, UniqueKey,
    discriminator, installed_measurements as model, string,
};
use serde::{Serialize, Serializer, ser::SerializeMap};
mod check;
mod partial;
pub(in crate::workbench::model_originals::workflow) use partial::Partial;

literal! { pub Recorded => "recorded" }
literal! { pub Publish => "publish" }
literal! { pub Revision => "0.1.0-draft.1" }
literal! { pub ClockDomain => "darwin-mach-continuous-nanoseconds" }
words! { pub Role { Outer=>"outer", Helper=>"transfer-helper" } }
tagged! { pub Launch("kind") {
    NodePackage=>"node-package"{runtime:model::implementation::OsOperand=>"runtime",entry:model::implementation::OsOperand=>"entry",helper:model::implementation::OsOperand=>"helper",directory:model::implementation::OsOperand=>"directory"},
    NativeExecutable=>"native-executable"{program:model::implementation::OsOperand=>"program",runtime:model::implementation::OsOperand=>"runtime",helper:model::implementation::OsOperand=>"helper",directory:model::implementation::OsOperand=>"directory"}
} }
record! { pub Association { process:Natural<0,{u64::MAX}> =>"processOrdinal",action:Natural<0,{u64::MAX}> =>"actionIndex",command:Publish=>"command",launch:Launch=>"launch" } }
tagged! { pub Clock("kind") {
    Unissued=>"unissued"{},
    Issued=>"issued"{domain:ClockDomain=>"domain",version:Revision=>"version",at:ExactU64=>"calibratedAtNs",end:ExactU64=>"endNs",numer:Natural<1,{u32::MAX as u64}> =>"timebaseNumer",denom:Natural<1,{u32::MAX as u64}> =>"timebaseDenom"}
} }
pub struct ExactU64(pub(super) u64);
impl std::fmt::Debug for ExactU64 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}
impl Decode for ExactU64 {
    fn decode(doc: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        Ok(Self(wire::Decimal::<false>::decode(doc, owner)?.value()))
    }
}
impl std::fmt::Display for ExactU64 {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Display::fmt(&self.0, f)
    }
}
impl Serialize for ExactU64 {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        s.collect_str(self)
    }
}
record! { pub Failure {phase:Text<1,128> =>"phase",code:Text<1,128> =>"code",message:Text<1,4096> =>"message"} }
tagged! { pub Completion("kind") {Drained=>"drained"{},Interrupted=>"interrupted"{first:Failure=>"firstFailure"}} }
tagged! { pub Terminal("kind") {
    NoFrame=>"no-frame"{},Header=>"header-prefix"{bytes:Natural<1,3> =>"bytes"},
    Body=>"body-prefix"{expected:Natural<0,{u32::MAX as u64}> =>"expected",bytes:Natural<0,{u32::MAX as u64}> =>"bytes"},
    Receiving=>"receiving"{},CloseRetained=>"close-retained"{},CloseAckWritten=>"close-ack-written"{},Drained=>"drained"{},Unused=>"unused"{}
} }
tagged! { pub Delivery("kind") {
    NotIssued=>"not-issued"{},Prefix=>"prefix"{written:Natural<0,128> =>"written",total:Natural<1,128> =>"total"},Written=>"written"{total:Natural<1,128> =>"total"}
} }
pub struct Row {
    pub(super) literal: Text<1, { u32::MAX as usize }>,
    pub(super) delivery: Delivery,
    pub(super) frame: wire::Frame,
}
impl std::fmt::Debug for Row {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Row")
            .field("literal", &self.literal)
            .field("delivery", &self.delivery)
            .finish()
    }
}
impl Decode for Row {
    fn decode(doc: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let fields = Fields::new(doc, &["literal", "delivery"], owner)?;
        let literal = fields.field::<Text<1, { u32::MAX as usize }>>("literal", owner)?;
        let delivery = fields.field("delivery", owner)?;
        // SAME saved Decoder funds the actual literal tree and raw-member pass.
        // Saved frames remain DATA, never receive/ACK or invocation authority.
        let (tree, raw) = owner.literal_with_raw(literal.as_str())?;
        let members = owner.raw_members(raw)?;
        for (key, value) in members {
            if matches!(
                key.as_str(),
                "sequence" | "attemptedHooks" | "startedFactFrames" | "retainedBusinessFacts"
            ) {
                let token = value.get();
                owner.bytes(token.len())?;
                if token.is_empty()
                    || !token.bytes().all(|b| b.is_ascii_digit())
                    || token.len() > 1 && token.starts_with('0')
                {
                    return Err(DecodeError::Shape("canonical saved consumer count"));
                }
            }
        }
        let frame = wire::Frame::decode(&tree, owner)?;
        Ok(Self {
            literal,
            delivery,
            frame,
        })
    }
}
impl Serialize for Row {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut map = s.serialize_map(Some(2))?;
        map.serialize_entry("literal", &self.literal)?;
        map.serialize_entry("delivery", &self.delivery)?;
        map.end()
    }
}
#[derive(Debug)]
pub struct EndpointFault(Option<Text<1, 128>>);
impl Decode for EndpointFault {
    fn decode(doc: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let value = Nullable::<Text<1, 128>>::decode(doc, owner)?.0;
        if let Some(value) = &value {
            let mut known = false;
            for kind in wire::ConsumerFailureKind::ALL {
                owner.bytes(
                    value
                        .as_str()
                        .len()
                        .checked_add(kind.code().len())
                        .ok_or(DecodeError::Limits)?,
                )?;
                if value.as_str() == kind.code() {
                    known = true;
                    break;
                }
            }
            if !known {
                return Err(DecodeError::Shape("closed consumer endpoint fault"));
            }
        }
        Ok(Self(value))
    }
}
impl Serialize for EndpointFault {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        self.0.serialize(s)
    }
}
record! { pub Endpoint {role:Role=>"role",terminal:Terminal=>"terminal",fault:EndpointFault =>"fault",frames:Items<Row,0,5> =>"frames"} }
record! { pub Record {kind:Recorded=>"kind",version:Revision=>"version",association:Association=>"association",clock:Clock=>"clock",completion:Completion=>"completion",endpoints:Items<Endpoint,2,2> =>"endpoints"} }
record! { pub FactRef {role:Role=>"role",sequence:Natural<0,{u64::MAX}> =>"sequence"} }
pub enum Dynamic {
    Unobserved,
    Observed {
        reference: FactRef,
        fact: wire::Fact,
    },
}
impl Dynamic {
    fn decode_kind(
        doc: &Document,
        owner: &mut Decoder,
        kind: report::FactKind,
    ) -> Result<Self, DecodeError> {
        if matches!(doc, Document::String(_)) {
            model::Unobserved::decode(doc, owner)?;
            return Ok(Self::Unobserved);
        }
        let names: &[&str] = match kind {
            report::FactKind::Release => &[
                "kind",
                "frameRef",
                "requestId",
                "captureId",
                "binding",
                "requestSha256",
                "replySha256",
            ],
            report::FactKind::Commit => &["kind", "frameRef", "path", "policy", "outcome"],
            report::FactKind::Cleanup => &["kind", "frameRef", "path", "outcome"],
        };
        let fields = Fields::new(doc, names, owner)?;
        let actual = fields.field::<Text<1, 32>>("kind", owner)?;
        if actual.as_str() != "observed" {
            return Err(DecodeError::Shape("consumer observed fact kind"));
        }
        let reference = fields.field("frameRef", owner)?;
        let fact = match kind {
            report::FactKind::Release => wire::Fact::Release {
                request: fields.field("requestId", owner)?,
                capture: fields.field("captureId", owner)?,
                binding: fields.field("binding", owner)?,
                request_sha: fields.field("requestSha256", owner)?,
                reply_sha: fields.field("replySha256", owner)?,
            },
            report::FactKind::Commit => wire::Fact::Commit {
                path: fields.field("path", owner)?,
                policy: fields.field("policy", owner)?,
                outcome: fields.field("outcome", owner)?,
            },
            report::FactKind::Cleanup => wire::Fact::Cleanup {
                path: fields.field("path", owner)?,
                outcome: fields.field("outcome", owner)?,
            },
        };
        Ok(Self::Observed { reference, fact })
    }
}
impl Serialize for Dynamic {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let Self::Observed { reference, fact } = self else {
            return s.serialize_str("unobserved");
        };
        let mut map = s.serialize_map(None)?;
        map.serialize_entry("kind", "observed")?;
        map.serialize_entry("frameRef", reference)?;
        super::report::fact_fields(fact, &mut map)?;
        map.end()
    }
}
pub(in crate::workbench::model_originals::workflow) struct Measurement {
    pub(super) record: Record,
    pub(super) release: Dynamic,
    pub(super) commit: Dynamic,
    pub(super) cleanup: Dynamic,
}
impl Measurement {
    pub(in crate::workbench::model_originals::workflow) fn decode(
        doc: &Document,
        owner: &mut Decoder,
    ) -> Result<Self, DecodeError> {
        let fields = Fields::new(
            doc,
            &[
                "implementation",
                "processes",
                "host",
                "destination",
                "publishedRelativeRoot",
                "scratch",
                "dynamicCommit",
                "dynamicScratchCleanup",
                "clientReleaseAcceptance",
                "consumerObservation",
            ],
            owner,
        )?;
        Ok(Self {
            record: fields.field("consumerObservation", owner)?,
            release: Dynamic::decode_kind(
                fields.document("clientReleaseAcceptance", owner)?,
                owner,
                report::FactKind::Release,
            )?,
            commit: Dynamic::decode_kind(
                fields.document("dynamicCommit", owner)?,
                owner,
                report::FactKind::Commit,
            )?,
            cleanup: Dynamic::decode_kind(
                fields.document("dynamicScratchCleanup", owner)?,
                owner,
                report::FactKind::Cleanup,
            )?,
        })
    }
    pub(in crate::workbench::model_originals::workflow) fn serialize_entries<
        S: serde::ser::SerializeMap,
    >(
        &self,
        map: &mut S,
    ) -> Result<(), S::Error> {
        map.serialize_entry("dynamicCommit", &self.commit)?;
        map.serialize_entry("dynamicScratchCleanup", &self.cleanup)?;
        map.serialize_entry("clientReleaseAcceptance", &self.release)?;
        map.serialize_entry("consumerObservation", &self.record)
    }
}
