//! The existing strict document/operand owner is the only decoder authority.
use super::*;
use crate::json::strict::Document;
use crate::workbench::model_originals::{
    CaptureId, ProjectId, ProviderId, SessionId, SourceIdentity, SourceLocator,
};

fn operand<T: Decode>(raw: &str, owner: &mut Decoder) -> Result<T, DecodeError> {
    owner.ready()?;
    let (document, _) = owner.literal_with_raw(raw)?;
    T::decode(&document, owner)
}
pub(in crate::workbench::model_originals::workflow) fn decode_input(
    raw: &str,
    owner: &mut Decoder,
) -> Result<OriginalScenario, DecodeError> {
    operand(raw, owner)
}
pub(in crate::workbench::model_originals::workflow) fn decode_expected(
    raw: &str,
    owner: &mut Decoder,
) -> Result<NativeDeclarationExpectation, DecodeError> {
    operand(raw, owner)
}
pub(in crate::workbench::model_originals::workflow) fn decode_observation(
    raw: &str,
    owner: &mut Decoder,
) -> Result<NativeDeclarationObservation, DecodeError> {
    operand(raw, owner)
}

impl Decode for ObservedCount {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        owner.bytes(text.len())?;
        if text.is_empty()
            || (text.len() > 1 && text.starts_with('0'))
            || !text.bytes().all(|byte| byte.is_ascii_digit())
        {
            return Err(DecodeError::Shape("canonical u64 decimal text"));
        }
        owner.bytes(text.len())?;
        text.parse::<u64>()
            .map(Self)
            .map_err(|_| DecodeError::Shape("u64 decimal overflow"))
    }
}
impl Decode for MeasurementVersion {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let text = string(value, owner)?;
        // Existing SemVer library, not a second general version grammar.
        owner.bytes(text.len())?;
        owner.slots(1)?;
        let parsed =
            semver::Version::parse(text).map_err(|_| DecodeError::Shape("measurement SemVer"))?;
        owner.bytes(MEASUREMENT_VERSION.len())?;
        if text != MEASUREMENT_VERSION {
            return Err(DecodeError::Shape("selected measurement draft"));
        }
        Ok(Self(parsed))
    }
}
macro_rules! identity {
    ($($ty:ty),* $(,)?) => {$(
        impl Decode for $ty {
            fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
                let text = string(value, owner)?;
                // The existing constructor validates Unicode controls then
                // copies its string. Reserve both passes on this same owner.
                owner.bytes(text.len())?;
                owner.bytes(text.len())?;
                owner.slots(1)?;
                Self::new(text).map_err(|_| DecodeError::Shape("model-originals identity"))
            }
        }
    )*};
}
identity!(CaptureId, ProjectId, ProviderId, SessionId, SourceLocator);
impl Decode for SourceIdentity {
    fn decode(value: &Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
        let fields = Fields::new(value, &["providerId", "locator"], owner)?;
        Ok(Self {
            provider: fields.field("providerId", owner)?,
            locator: fields.field("locator", owner)?,
        })
    }
}
