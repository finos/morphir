//! Private staged corpus operand binding, not a registered workbench version.
//!
//! The parent retains the enclosing immutable bytes for this borrow. Tokens
//! retain their original interior whitespace and lexemes; enclosing whitespace
//! belongs to the full source, not to either operand token. No original-packet,
//! manifest, filesystem-source, authority or runtime proof is issued here.
use super::pairing::{PairError, PairedWorkflow};
use super::{DecodeError, Decoder, Fields, UniqueKey, domain, input, string};
use crate::json::strict::Document;
use serde_json::value::RawValue;

#[derive(Debug)]
pub(super) enum IngressError {
    Decode(DecodeError),
    DuplicateCase,
    CaseId,
    Pair(PairError),
}
impl From<DecodeError> for IngressError {
    fn from(error: DecodeError) -> Self {
        Self::Decode(error)
    }
}

pub(super) struct BoundCorpus<'source> {
    raw: &'source str,
    cases: Vec<BoundCase<'source>>,
}
pub(super) struct BoundCase<'source> {
    id: CorpusCaseId,
    input_token: &'source RawValue,
    expected_token: &'source RawValue,
    operands: BoundOperands,
}
enum BoundOperands {
    Current {
        input: input::Scenario,
        expected: domain::ExpectedWorkflow,
    },
    OriginalDeclaration {
        input: super::native_original::OriginalScenario,
        expected: super::native_original::NativeDeclarationExpectation,
    },
}
fn original_expected(document: &Document, owner: &mut Decoder) -> Result<bool, DecodeError> {
    let Document::Object(fields) = document else {
        return Ok(false);
    };
    for (key, value) in fields {
        owner.bytes(key.len().saturating_add(4))?;
        if key == "kind" {
            let value = string(value, owner)?;
            const KIND: &str = "concrete-native-declaration-workflow-expectation";
            owner.bytes(value.len().saturating_add(KIND.len()))?;
            return Ok(value == KIND);
        }
    }
    Ok(false)
}

/// Uses the existing workbench identity policy, independently of fixture
/// aliases and the IR kit's more restrictive topic-and-number identifiers.
#[derive(PartialEq, Eq)]
pub(super) struct CorpusCaseId(String);

impl CorpusCaseId {
    pub(super) fn parse(value: &str, owner: &mut Decoder) -> Result<Self, IngressError> {
        owner.bytes(value.len())?;
        crate::workbench::contract::identity(value, 128).map_err(|_| IngressError::CaseId)?;
        owner.bytes(value.len())?;
        Ok(Self(value.to_owned()))
    }

    pub(super) fn as_str(&self) -> &str {
        &self.0
    }
}

fn pair_with_work<'source>(
    input: &'source input::Scenario,
    expected: &'source domain::ExpectedWorkflow,
    owner: &mut Decoder,
) -> Result<PairedWorkflow<'source>, IngressError> {
    owner.ready()?;
    let origin = match expected {
        domain::ExpectedWorkflow::ModelOriginalsServer { origin, .. }
        | domain::ExpectedWorkflow::ModelOriginalsClient { origin, .. } => origin,
    };
    owner.bytes(input.origin.packet.key().len())?;
    owner.bytes(origin.packet.key().len())?;
    owner.bytes(input.origin.sha256.0.len() + origin.sha256.0.len())?;
    owner.bytes(input.origin.id.0.len())?;
    owner.bytes(origin.id.0.len())?;
    PairedWorkflow::new(input, expected).map_err(IngressError::Pair)
}

fn raw_field<'source>(
    members: &[(String, &'source RawValue)],
    name: &str,
    owner: &mut Decoder,
) -> Result<&'source RawValue, DecodeError> {
    owner.ready()?;
    for (key, value) in members {
        owner.bytes(key.len().saturating_add(name.len()))?;
        if key == name {
            return Ok(value);
        }
    }
    Err(DecodeError::Shape("required raw object field"))
}

impl<'source> BoundCorpus<'source> {
    /// Only parent-selected bytes are bound. Equal origin claims remain
    /// metadata; neither the caller nor this method can issue packet trust.
    pub(super) fn decode(raw: &'source str, owner: &mut Decoder) -> Result<Self, IngressError> {
        Self::decode_header(raw, owner, false)
    }
    pub(super) fn decode_selected(
        raw: &'source str,
        owner: &mut Decoder,
    ) -> Result<Self, IngressError> {
        Self::decode_header(raw, owner, true)
    }
    fn decode_header(
        raw: &'source str,
        owner: &mut Decoder,
        selected: bool,
    ) -> Result<Self, IngressError> {
        let (document, raw_root) = owner.literal_with_raw(raw)?;
        let root_fields = Fields::new(
            &document,
            if selected {
                &["formatVersion", "cases"]
            } else {
                &["cases"]
            },
            owner,
        )?;
        if selected
            && string(root_fields.document("formatVersion", owner)?, owner)? != "0.1.0-draft.30"
        {
            return Err(DecodeError::Shape("selected corpus draft").into());
        }
        let cases_document = root_fields.document("cases", owner)?;
        owner.ready()?;
        let Document::Array(items) = cases_document else {
            return Err(DecodeError::Shape("corpus cases array").into());
        };
        let root_members = owner.raw_members(raw_root)?;
        let raw_cases = raw_field(&root_members, "cases", owner)?;
        let raw_items = owner.raw_elements(raw_cases)?;
        if raw_items.len() != items.len() {
            return Err(DecodeError::Shape("raw and decoded case correspondence").into());
        }
        owner.slots(items.len())?;
        let mut cases: Vec<BoundCase<'source>> = Vec::new();
        cases
            .try_reserve_exact(items.len())
            .map_err(|_| DecodeError::Allocation)?;
        for (item, raw_item) in items.iter().zip(raw_items) {
            let fields = Fields::new(item, &["id", "input", "expected"], owner)?;
            let id = string(fields.document("id", owner)?, owner)?;
            let id = CorpusCaseId::parse(id, owner)?;
            for previous in &cases {
                owner.bytes(previous.id.as_str().len().saturating_add(id.as_str().len()))?;
                if previous.id == id {
                    return Err(IngressError::DuplicateCase);
                }
            }
            let operands = if original_expected(fields.document("expected", owner)?, owner)? {
                BoundOperands::OriginalDeclaration {
                    input: fields.field("input", owner)?,
                    expected: fields.field("expected", owner)?,
                }
            } else {
                BoundOperands::Current {
                    input: fields.field("input", owner)?,
                    expected: fields.field("expected", owner)?,
                }
            };
            owner.ready()?;
            if let BoundOperands::Current { input, expected } = &operands {
                pair_with_work(input, expected, owner)?;
            }
            let members = owner.raw_members(raw_item)?;
            let input_token = raw_field(&members, "input", owner)?;
            let expected_token = raw_field(&members, "expected", owner)?;
            // The only string retained beyond the decoder's Document is the
            // actual case ID. Operand bytes remain borrowed, with no copy.
            cases.push(BoundCase {
                id,
                input_token,
                expected_token,
                operands,
            });
        }
        Ok(Self { raw, cases })
    }
    pub(super) fn raw(&self) -> &'source str {
        self.raw
    }
    pub(super) fn cases(&self) -> &[BoundCase<'source>] {
        &self.cases
    }
}

impl<'source> BoundCase<'source> {
    pub(super) fn id(&self) -> &str {
        self.id.as_str()
    }
    pub(super) fn input_token(&self) -> &'source str {
        self.input_token.get()
    }
    pub(super) fn expected_token(&self) -> &'source str {
        self.expected_token.get()
    }
    pub(super) fn input_raw(&self) -> &'source RawValue {
        self.input_token
    }
    pub(super) fn expected_raw(&self) -> &'source RawValue {
        self.expected_token
    }
    /// The typed operands are private and immutable, so this reuses the
    /// genuine pairing boundary without a self-reference or lifetime erasure.
    pub(super) fn paired(&self) -> Result<PairedWorkflow<'_>, PairError> {
        match &self.operands {
            BoundOperands::Current { input, expected } => PairedWorkflow::new(input, expected),
            BoundOperands::OriginalDeclaration { .. } => Err(PairError::Role),
        }
    }

    pub(super) fn paired_with_work(
        &self,
        owner: &mut Decoder,
    ) -> Result<PairedWorkflow<'_>, IngressError> {
        match &self.operands {
            BoundOperands::Current { input, expected } => pair_with_work(input, expected, owner),
            BoundOperands::OriginalDeclaration { .. } => Err(IngressError::Pair(PairError::Role)),
        }
    }
    pub(super) fn native_operands(
        &self,
    ) -> Option<(
        &super::native_original::OriginalScenario,
        &super::native_original::NativeDeclarationExpectation,
    )> {
        match &self.operands {
            BoundOperands::OriginalDeclaration { input, expected } => Some((input, expected)),
            BoundOperands::Current { .. } => None,
        }
    }
}

#[cfg(test)]
mod tests;

#[cfg(test)]
mod source_tests;

#[cfg(test)]
mod id_tests;

#[cfg(test)]
mod pairing_work_tests;
