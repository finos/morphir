//! The actual read-run shape and work calculation, shared by saved input and
//! typed workflow compilation. A plan grants no pending-effect delivery authority.
use super::*;

#[derive(Clone, Copy)]
pub(in crate::workbench::model_originals) enum ReplyPartView<'a> {
    Literal(&'a str),
    CorrelatedRequestId,
    RowOffset,
    RowNextOffset,
    Base64Window,
}
/// Work-only bounds. Saved-input decoding has its own genuine boundary owner.
pub(in crate::workbench::model_originals) struct ReadWorkBounds {
    pub rows: usize,
    pub window_bytes: usize,
    pub wire_bytes: usize,
    pub observer_bytes: usize,
}
impl From<PeerReadBounds> for ReadWorkBounds {
    fn from(bounds: PeerReadBounds) -> Self {
        Self {
            rows: bounds.rows,
            window_bytes: bounds.window_bytes,
            wire_bytes: bounds.wire_bytes,
            observer_bytes: bounds.observer_bytes,
        }
    }
}
pub(in crate::workbench::model_originals) struct ReadRunShape {
    source_length: usize,
    window: SavedWindow,
}
impl ReadRunShape {
    pub(in crate::workbench::model_originals) fn new(
        source_length: usize,
        first_ordinal: usize,
        first_offset: usize,
        after_offset: usize,
        chunk_bytes: usize,
        rows: usize,
    ) -> Result<Self, PeerReadError> {
        let first = Ordinal::new(first_ordinal)?;
        if source_length > 64 * 1024 * 1024
            || first_offset >= after_offset
            || after_offset > source_length
            || !(1..=65536).contains(&chunk_bytes)
            || !(1..=MAX_ROWS).contains(&rows)
        {
            return Err(PeerReadError::Range);
        }
        let span = after_offset - first_offset;
        if span.div_ceil(chunk_bytes) != rows
            || (after_offset < source_length && !span.is_multiple_of(chunk_bytes))
            || first.0.checked_add(rows).is_none_or(|end| end > MAX_ROWS)
        {
            return Err(PeerReadError::Range);
        }
        Ok(Self {
            source_length,
            window: SavedWindow {
                first_offset,
                after_offset,
                chunk_bytes,
                rows,
            },
        })
    }
    pub(in crate::workbench::model_originals) fn measure<'a>(
        &self,
        parts: impl Clone + ExactSizeIterator<Item = ReplyPartView<'a>>,
        bounds: ReadWorkBounds,
    ) -> Result<PeerReadWork, PeerReadError> {
        if parts.len() == 0
            || parts.len() > 32
            || parts
                .clone()
                .any(|part| matches!(part,ReplyPartView::Literal(text) if text.len()>16*1024))
        {
            return Err(PeerReadError::Shape);
        }
        let mut work = PeerReadWork {
            rows: self.window.rows,
            window_bytes: 0,
            wire_bytes: 0,
            observer_bytes: 0,
        };
        for row in 0..self.window.rows {
            let offset = add(self.window.first_offset, mul(row, self.window.chunk_bytes)?)?;
            let size = self.window.chunk_bytes.min(self.source_length - offset);
            let next = add(offset, size)?;
            let payload = mul(size.div_ceil(3), 4)?;
            let frame = frame_length(parts.clone(), 20, offset, next, payload)?;
            if frame > MAX_REPLY_BYTES {
                return Err(PeerReadError::Range);
            }
            work.window_bytes = add(work.window_bytes, size)?;
            work.wire_bytes = add(work.wire_bytes, add(MAX_REQUEST_BYTES, frame)?)?;
            work.observer_bytes = add(
                work.observer_bytes,
                add(add(mul(size, 3)?, payload)?, mul(frame, 2)?)?,
            )?;
        }
        work.check(bounds)?;
        Ok(work)
    }
}
fn decimal_width(number: usize) -> usize {
    if number == 0 {
        1
    } else {
        number.ilog10() as usize + 1
    }
}
pub(super) fn frame_length<'a>(
    mut parts: impl Iterator<Item = ReplyPartView<'a>>,
    id_width: usize,
    offset: usize,
    next: usize,
    payload: usize,
) -> Result<usize, PeerReadError> {
    parts.try_fold(0, |total, part| {
        add(
            total,
            match part {
                ReplyPartView::Literal(text) => text.len(),
                ReplyPartView::CorrelatedRequestId => id_width,
                ReplyPartView::RowOffset => decimal_width(offset),
                ReplyPartView::RowNextOffset => decimal_width(next),
                ReplyPartView::Base64Window => payload,
            },
        )
    })
}
