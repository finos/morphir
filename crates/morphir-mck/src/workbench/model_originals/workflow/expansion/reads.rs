//! Borrowed workflow operands feed the genuine existing peer-read planner.
//! Source references are resolved against input files, never expected/observed bytes.
use super::*;
use crate::workbench::model_originals::{
    FixtureAlias, PeerReadError,
    peer_read::{ReadRunShape, ReadWorkBounds, ReplyPartView},
};

pub(super) struct ReadRunInput<'a> {
    pub source: &'a FixtureAlias,
    pub first_ordinal: u64,
    pub window: &'a input::ClientActionReadRunWindow,
    pub parts: &'a [input::ReadRunPart],
    pub effect_kind: &'a input::ClientActionReadRunEffectKind,
    pub expected: &'a input::ClientActionReadRunExpectedRequest,
}
fn part(part: &input::ReadRunPart) -> ReplyPartView<'_> {
    match part {
        input::ReadRunPart::Literal { text } => ReplyPartView::Literal(&text.0),
        input::ReadRunPart::CorrelatedRequestId {} => ReplyPartView::CorrelatedRequestId,
        input::ReadRunPart::RowOffset {} => ReplyPartView::RowOffset,
        input::ReadRunPart::RowNextOffset {} => ReplyPartView::RowNextOffset,
        input::ReadRunPart::Base64Window {} => ReplyPartView::Base64Window,
    }
}
impl ExpansionOwner {
    fn length(&mut self, recipe: &input::Bytes) -> Result<u64, ExpansionError> {
        self.visit()?;
        match recipe {
            // This opaque AST leaf was already validated by the same Decoder.
            // Length lookup must not rescan a large source for every read run.
            input::Bytes::Hex { hex } => Ok((hex.as_str().len() / 2) as u64),
            input::Bytes::Utf8 { text } => Ok(text.0.len() as u64),
            input::Bytes::RepeatU8 { length, .. }
            | input::Bytes::CycleU8 { length, .. }
            | input::Bytes::ChunkIndexedU8 { length, .. } => Ok(length.0),
            input::Bytes::Concat { parts } => {
                let mut total = 0u64;
                for atom in &parts.0 {
                    self.visit()?;
                    let length = match atom {
                        input::AtomicBytes::Hex { hex } => (hex.as_str().len() / 2) as u64,
                        input::AtomicBytes::Utf8 { text } => text.0.len() as u64,
                        input::AtomicBytes::RepeatU8 { length, .. }
                        | input::AtomicBytes::CycleU8 { length, .. }
                        | input::AtomicBytes::ChunkIndexedU8 { length, .. } => length.0,
                    };
                    total = match total.checked_add(length) {
                        Some(total) => total,
                        None => {
                            return self.refuse(ExpansionError::Arithmetic(
                                ExpansionResource::RecipeBytes,
                            ));
                        }
                    };
                }
                Ok(total)
            }
        }
    }
    fn remaining_read(&self, resource: ExpansionResource) -> usize {
        // This clamps an explicitly supplied ceiling to this target's addressable
        // range. The shared planner still enforces its own finite protocol bounds.
        usize::try_from(self.limits.0.amount(resource) - self.used.amount(resource))
            .unwrap_or(usize::MAX)
    }
}
pub(super) fn measure(
    owner: &mut ExpansionOwner,
    fixture: &input::ClientFixture,
    run: ReadRunInput<'_>,
) -> Result<(), ExpansionError> {
    owner.charge(ExpansionResource::ReadRows, run.window.rows.0)?;
    let mut source = None;
    for file in &fixture.files.0 {
        owner.visit()?;
        if &file.alias == run.source {
            if source.is_some() {
                return owner.refuse(ExpansionError::ReadSourceAmbiguous);
            }
            source = Some(&file.bytes);
        }
    }
    let Some(source) = source else {
        return owner.refuse(ExpansionError::ReadSourceMissing);
    };
    let length = match owner.length(source) {
        Ok(length) => length,
        Err(error) => return owner.refuse(error),
    };
    let expected_kind = matches!(
        (run.effect_kind, &run.expected.target),
        (
            input::ClientActionReadRunEffectKind::ReadOriginal,
            input::ReadTarget::Original { .. }
        ) | (
            input::ClientActionReadRunEffectKind::ReadProjection,
            input::ReadTarget::SemanticProjection {}
        )
    );
    if !expected_kind || run.expected.max_bytes.0 != run.window.chunk_bytes.0 {
        return owner.refuse(ExpansionError::ReadPlan(PeerReadError::Request));
    }
    let count = |value: u64| usize::try_from(value).map_err(|_| PeerReadError::Range);
    let plan = (|| {
        ReadRunShape::new(
            count(length)?,
            count(run.first_ordinal)?,
            count(run.window.first_offset.0)?,
            count(run.window.after_offset.0)?,
            count(run.window.chunk_bytes.0)?,
            count(run.window.rows.0)?,
        )
    })();
    let shape = match plan {
        Ok(shape) => shape,
        Err(error) => return owner.refuse(ExpansionError::ReadPlan(error)),
    };
    let bounds = ReadWorkBounds {
        rows: run.window.rows.0 as usize,
        window_bytes: owner.remaining_read(ExpansionResource::ReadWindowBytes),
        wire_bytes: owner.remaining_read(ExpansionResource::ReadWireBytes),
        observer_bytes: owner.remaining_read(ExpansionResource::ReadObserverBytes),
    };
    let work = match shape.measure(run.parts.iter().map(part), bounds) {
        Ok(work) => work,
        Err(error) => return owner.refuse(ExpansionError::ReadPlan(error)),
    };
    owner.charge(
        ExpansionResource::ReadWindowBytes,
        work.window_bytes() as u64,
    )?;
    owner.charge(ExpansionResource::ReadWireBytes, work.wire_bytes() as u64)?;
    owner.charge(
        ExpansionResource::ReadObserverBytes,
        work.observer_bytes() as u64,
    )?;
    Ok(())
}
