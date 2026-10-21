use super::*;
use crate::json::strict::Document;
use crate::workbench::model_originals::workflow::decode::{Decode, DecodeError, discriminator};
use wire::{ConsumerCodecError as Error, DecodedConsumerEnvelope, DecodedRetained};

impl InstalledClientRun<'_> {
    pub(super) fn consumer_fault(&mut self, error: Error) -> Error {
        self.attempt.fail(RunFault::InstalledConsumer(error));
        error
    }
    pub(super) fn check_consumer_ports(
        &mut self,
        ports: &InstalledConsumerPorts,
    ) -> Result<(), Error> {
        self.work_ready().map_err(|_| Error::PriorFault)?;
        if !self.revoker.matches(&ports.control.invocation) || ports.control.revoked() {
            return Err(self.consumer_fault(Error::Association));
        }
        if Instant::now() >= ports.control.end {
            ports.control.revoke();
            return Err(self.consumer_fault(Error::Expired));
        }
        Ok(())
    }
    fn decode_error(&mut self, error: DecodeError) -> Error {
        if matches!(error, DecodeError::Allocation) || self.decode.ready().is_err() {
            self.attempt.fail(RunFault::Decode(error));
            return Error::Decode;
        }
        match error {
            DecodeError::Literal(_) => Error::Json,
            _ => Error::Shape,
        }
    }
    pub(super) fn consumer_decode<T>(
        &mut self,
        result: Result<T, DecodeError>,
    ) -> Result<T, Error> {
        result.map_err(|error| self.decode_error(error))
    }
    fn codec_document<'a>(
        &mut self,
        payload: &'a [u8],
    ) -> Result<(Document, &'a serde_json::value::RawValue), Error> {
        self.work_ready().map_err(|_| Error::PriorFault)?;
        self.visit_observation_bytes(payload.len())
            .map_err(|_| Error::PriorFault)?;
        let raw = std::str::from_utf8(payload).map_err(|_| Error::Utf8)?;
        // Source-pinned requested capacities for the strict tree, ONE extra
        // raw-members pass, typed copies and terminal diagnostics, including
        // an empty input. This is separate from actual literal/cache capacity
        // and cumulative parser work, and is not allocator/RSS accounting.
        let span = crate::json::strict::requested_document_storage_bound(payload.len())
            .and_then(|document| {
                crate::json::strict::requested_raw_members_storage_bound(payload.len())
                    .and_then(|raw| document.checked_add(raw))
            })
            .and_then(|parsed| {
                crate::json::strict::requested_codec_typed_storage_bound(
                    payload.len(),
                    std::mem::size_of::<wire::Operand>(),
                )
                .and_then(|typed| parsed.checked_add(typed))
            })
            .and_then(|copies| {
                crate::json::strict::requested_diagnostic_storage_bound(payload.len())
                    .and_then(|diagnostic| copies.checked_add(diagnostic))
            })
            .ok_or_else(|| {
                self.overflow_failure();
                Error::Resource(InstalledObservationError::SizeOverflow)
            })?;
        self.reserve_storage(span)
            .map_err(|_| self.consumer_receiving_error())?;
        let result = self.decode.slots(payload.len());
        self.consumer_decode(result)?;
        let result = self.decode.literal_with_raw(raw);
        self.consumer_decode(result)
    }
    fn consumer_canonical_counts(
        &mut self,
        raw: &serde_json::value::RawValue,
    ) -> Result<(), Error> {
        // Number's typed representation can normalize -0. Retain the original
        // numeric tokens from this SAME literal, using its existing charged
        // raw-member helper before the closed typed conversion.
        let result = self.decode.raw_members(raw);
        let members = self.consumer_decode(result)?;
        for (key, value) in members {
            self.visit_observation_bytes(key.len().saturating_mul(4).saturating_add(56))
                .map_err(|_| Error::PriorFault)?;
            if matches!(
                key.as_str(),
                "sequence" | "attemptedHooks" | "startedFactFrames" | "retainedBusinessFacts"
            ) {
                let token = value.get();
                self.visit_observation_bytes(token.len().saturating_mul(2))
                    .map_err(|_| Error::PriorFault)?;
                if token.is_empty()
                    || !token.bytes().all(|byte| byte.is_ascii_digit())
                    || (token.len() > 1 && token.starts_with('0'))
                {
                    return Err(Error::Shape);
                }
            }
        }
        Ok(())
    }
    pub(super) fn consumer_receiving_error(&mut self) -> Error {
        match self.receiving.ready() {
            Err(error) => Error::Resource(*error),
            Ok(()) => Error::PriorFault,
        }
    }
    fn consumer_literal(&mut self, raw: &[u8]) -> Result<String, Error> {
        let visits = raw.len().checked_mul(2).ok_or_else(|| {
            self.overflow_failure();
            Error::Resource(InstalledObservationError::SizeOverflow)
        })?;
        self.reserve_storage(raw.len())
            .map_err(|_| self.consumer_receiving_error())?;
        let mut result = String::new();
        result.try_reserve_exact(raw.len()).map_err(|_| {
            self.allocate_failure();
            Error::Resource(InstalledObservationError::Allocation)
        })?;
        self.storage_excess(raw.len(), result.capacity())
            .map_err(|_| self.consumer_receiving_error())?;
        self.visit_observation_bytes(visits)
            .map_err(|_| Error::PriorFault)?;
        result.push_str(std::str::from_utf8(raw).map_err(|_| Error::Utf8)?);
        Ok(result)
    }
    fn consumer_payload<'a>(
        &mut self,
        ports: &InstalledConsumerPorts,
        framed: &'a [u8],
    ) -> Result<&'a [u8], Error> {
        self.check_consumer_ports(ports)?;
        if framed.len() < 4 {
            return Err(Error::Framing);
        }
        self.visit_observation_bytes(4)
            .map_err(|_| Error::PriorFault)?;
        let length = u32::from_be_bytes(framed[..4].try_into().expect("four bytes")) as usize;
        if length > ports.control.max_frame {
            return Err(Error::FrameTooLarge);
        }
        if length.checked_add(4) != Some(framed.len()) {
            return Err(Error::Framing);
        }
        Ok(&framed[4..])
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn decode_consumer_frame_literal(
        &mut self,
        ports: &InstalledConsumerPorts,
        role: ConsumerProducerRole,
        framed: &[u8],
    ) -> Result<DecodedConsumerEnvelope, Error> {
        let payload = self.consumer_payload(ports, framed)?;
        self.consumer_decode_body(role, payload)
    }
    pub(super) fn consumer_decode_body(
        &mut self,
        role: ConsumerProducerRole,
        payload: &[u8],
    ) -> Result<DecodedConsumerEnvelope, Error> {
        let (document, raw) = self.codec_document(payload)?;
        self.consumer_canonical_counts(raw)?;
        let result = discriminator(&document, "kind", self.decode);
        let kind = self.consumer_decode(result)?;
        if kind == "retained" {
            return Err(Error::Direction);
        }
        let result = wire::Frame::decode(&document, self.decode);
        let frame = self.consumer_decode(result)?;
        frame.validate(role, self.decode).inspect_err(|_| {
            if let Err(fault) = self.decode.ready() {
                self.attempt.fail(RunFault::Decode(fault));
            }
        })?;
        let literal = self.consumer_literal(payload)?;
        Ok(DecodedConsumerEnvelope { frame, literal })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn decode_consumer_ack_literal(
        &mut self,
        ports: &InstalledConsumerPorts,
        _role: ConsumerProducerRole,
        framed: &[u8],
    ) -> Result<DecodedRetained, Error> {
        let payload = self.consumer_payload(ports, framed)?;
        let (document, raw) = self.codec_document(payload)?;
        self.consumer_canonical_counts(raw)?;
        let result = discriminator(&document, "kind", self.decode);
        let kind = self.consumer_decode(result)?;
        if kind != "retained" {
            return Err(Error::Direction);
        }
        let result = wire::Retained::decode(&document, self.decode);
        let ack = self.consumer_decode(result)?;
        self.visit_observation_bytes(ack.version.0.len().saturating_add(wire::VERSION.len()))
            .map_err(|_| Error::PriorFault)?;
        if ack.version.0 != wire::VERSION {
            return Err(Error::Revision);
        }
        Ok(DecodedRetained {
            sequence: ack.sequence.0,
            literal: self.consumer_literal(payload)?,
        })
    }
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::installed::adapter) fn test_consumer_cache(
        &self,
        role: ConsumerProducerRole,
    ) -> &[DecodedConsumerEnvelope] {
        &self.consumer_cache[role.index()]
    }
}
impl ConsumerProducerRole {
    pub(super) fn index(self) -> usize {
        match self {
            Self::Outer => 0,
            Self::TransferHelper => 1,
        }
    }
}
