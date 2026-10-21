//! DATA-only adapters of the same production reservation, preflight and writer.
use super::*;
use std::cell::RefCell;

impl OutputRequirements {
    pub(in crate::workbench::model_originals::workflow) fn test_report_limit(&self) -> usize {
        self.report_limit
    }
    pub(in crate::workbench::model_originals::workflow) fn test_diagnostic_bytes(&self) -> usize {
        self.diagnostic
    }
    pub(in crate::workbench::model_originals::workflow) fn test_retained_bytes(&self) -> usize {
        self.retained
    }
}
impl ReservedConsumerOutput {
    pub(in crate::workbench::model_originals::workflow) fn test_report_limit(&self) -> usize {
        self.requirements.report_limit
    }
    pub(in crate::workbench::model_originals::workflow) fn test_work_bound(&self) -> usize {
        self.requirements.visits
    }
    pub(in crate::workbench::model_originals::workflow) fn test_capacity(&self) -> usize {
        self.destination.capacity()
    }
}
impl EncodedConsumerOutput {
    pub(in crate::workbench::model_originals::workflow) fn test_capacity(&self) -> usize {
        self.text.capacity()
    }
    pub(in crate::workbench::model_originals::workflow) fn test_bytes(&self) -> &[u8] {
        self.text.as_bytes()
    }
}
#[derive(Debug)]
pub(in crate::workbench::model_originals::workflow) struct DataRejected<'a, T: ?Sized> {
    data: &'a T,
    rejected: BufferRejected,
}
impl<'a, T: ?Sized> DataRejected<'a, T> {
    pub(in crate::workbench::model_originals::workflow) fn test_capacity(&self) -> usize {
        self.rejected.output.destination.capacity()
    }
    pub(in crate::workbench::model_originals::workflow) fn test_retained_data(&self) -> &'a T {
        self.data
    }
    pub(in crate::workbench::model_originals::workflow) fn test_is_limit_refusal(&self) -> bool {
        self.rejected.fault == ConsumerEncodingFault::Limit
    }
    pub(in crate::workbench::model_originals::workflow) fn test_serializer_passes(&self) -> usize {
        self.rejected.passes
    }
    pub(in crate::workbench::model_originals::workflow) fn test_is_preflight_work_refusal(
        &self,
    ) -> bool {
        self.rejected.fault == ConsumerEncodingFault::WorkLimit
    }
    pub(in crate::workbench::model_originals::workflow) fn test_is_preflight_string_refusal(
        &self,
    ) -> bool {
        self.rejected.fault == ConsumerEncodingFault::Limit
    }
    pub(in crate::workbench::model_originals::workflow) fn test_preflight_string_bytes(
        &self,
    ) -> usize {
        self.rejected.progress.strings
    }
    pub(in crate::workbench::model_originals::workflow) fn test_preflight_steps(&self) -> usize {
        self.rejected.progress.steps
    }
    pub(in crate::workbench::model_originals::workflow) fn test_retry(
        &mut self,
        run: &mut InstalledClientRun<'_>,
    ) -> Result<(), ConsumerEncodingFault> {
        // Exercise the SAME production readiness boundary. An omitted sticky
        // failure would return Ok and fail the control, without reusing the
        // consumed unique writer or obtaining fresh work/storage permission.
        run.work_ready()
            .map_err(|_| ConsumerEncodingFault::PriorFault)
    }
}
pub(in crate::workbench::model_originals::workflow) struct RecordRejected {
    record: record::ConsumerOperationRecord,
    rejected: BufferRejected,
}
impl std::fmt::Debug for RecordRejected {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RecordRejected")
            .field("rejected", &self.rejected)
            .finish_non_exhaustive()
    }
}
impl RecordRejected {
    pub(in crate::workbench::model_originals::workflow) fn test_projected_process(
        &self,
    ) -> (
        &data::ProcessMeasurement,
        &crate::transport::process::ProcessOutcome,
    ) {
        projected(&self.record).expect("projected actual record")
    }
    pub(in crate::workbench::model_originals::workflow) fn test_record(
        &self,
    ) -> &record::ConsumerOperationRecord {
        &self.record
    }
    pub(in crate::workbench::model_originals::workflow) fn test_is_limit_refusal(&self) -> bool {
        self.rejected.fault == ConsumerEncodingFault::Limit
    }
}
pub(in crate::workbench::model_originals::workflow) struct PrefixData {
    bytes: data::ObservedBytes,
    output: RefCell<Option<ReservedConsumerOutput>>,
}
impl std::fmt::Debug for PrefixData {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("PrefixData")
            .field("bytes", &self.bytes)
            .finish_non_exhaustive()
    }
}
impl PrefixData {
    pub(in crate::workbench::model_originals::workflow) fn test_bytes(&self) -> &[u8] {
        self.bytes.as_bytes()
    }
    pub(in crate::workbench::model_originals::workflow) fn test_raw_capacity(&self) -> usize {
        self.bytes.test_raw_capacity()
    }
    pub(in crate::workbench::model_originals::workflow) fn test_encode_with_reserved_writer(
        &self,
    ) -> Result<serde_json::Value, ConsumerEncodingFault> {
        let output = self
            .output
            .borrow_mut()
            .take()
            .ok_or(ConsumerEncodingFault::PriorFault)?;
        let bound = output.requirements.report_limit;
        let encoded =
            encode(output, &self.bytes, bound, bound).map_err(|rejected| rejected.fault)?;
        // Diagnostic decoding of explicit unit DATA only. No runtime authority.
        serde_json::from_str(&encoded.text).map_err(|_| ConsumerEncodingFault::Serialization)
    }
}
impl InstalledClientRun<'_> {
    pub(in crate::workbench::model_originals::workflow) fn test_consumer_output_requirements(
        &mut self,
        limits: Limits,
    ) -> Result<OutputRequirements, InstalledAdapterError> {
        self.consumer_output_requirements(limits)
    }
    pub(in crate::workbench::model_originals::workflow) fn test_prepare_consumer_output(
        &mut self,
        limits: Limits,
    ) -> Result<ReservedConsumerOutput, InstalledAdapterError> {
        self.prepare_consumer_output(limits)
    }
    pub(in crate::workbench::model_originals::workflow) fn test_project_consumer_record(
        &mut self,
    ) -> Result<(), ConsumerEncodingFault> {
        self.collected
            .consumer
            .as_mut()
            .ok_or(ConsumerEncodingFault::Unsupported)?
            .project_process()
    }
    pub(in crate::workbench::model_originals::workflow) fn test_consumer_projected_process(
        &self,
    ) -> Option<(
        &data::ProcessMeasurement,
        &crate::transport::process::ProcessOutcome,
    )> {
        self.collected.consumer.as_ref()?.projected_process()
    }
    pub(in crate::workbench::model_originals::workflow) fn test_reject_consumer_encoding_at(
        &mut self,
        bound: usize,
    ) -> Result<EncodedConsumerOutput, RecordRejected> {
        let mut record = self
            .collected
            .consumer
            .take()
            .expect("retained actual record");
        let output = record
            .reservation
            .output
            .take()
            .expect("single preissued output");
        let steps = output.requirements.report_limit;
        match encode(
            output,
            projected(&record).expect("projected actual record").0,
            bound,
            steps,
        ) {
            Ok(encoded) => Ok(encoded),
            Err(rejected) => {
                self.encoding_fault(rejected.fault);
                Err(RecordRejected { record, rejected })
            }
        }
    }
    pub(in crate::workbench::model_originals::workflow) fn test_encode_retained_report_data<'a>(
        &mut self,
        output: ReservedConsumerOutput,
        value: &'a serde_json::value::RawValue,
        bound: usize,
    ) -> Result<EncodedConsumerOutput, DataRejected<'a, [u8]>> {
        let steps = output.requirements.report_limit;
        encode(output, value, bound, steps).map_err(|rejected| {
            self.encoding_fault(rejected.fault);
            DataRejected {
                data: value.get().as_bytes(),
                rejected,
            }
        })
    }
    pub(in crate::workbench::model_originals::workflow) fn test_encode_consumer_data_with_preflight<
        'a,
    >(
        &mut self,
        output: ReservedConsumerOutput,
        value: &'a serde_json::Value,
        bound: usize,
        steps: usize,
    ) -> Result<EncodedConsumerOutput, DataRejected<'a, serde_json::Value>> {
        encode(output, value, bound, steps).map_err(|rejected| {
            self.encoding_fault(rejected.fault);
            DataRejected {
                data: value,
                rejected,
            }
        })
    }
    pub(in crate::workbench::model_originals::workflow) fn test_adopt_consumer_prefix_data(
        &mut self,
        mut output: ReservedConsumerOutput,
        bytes: Vec<u8>,
    ) -> Result<PrefixData, ConsumerEncodingFault> {
        if bytes.len() > output.requirements.stdout {
            return Err(ConsumerEncodingFault::Limit);
        }
        let (permission, _unused) = output
            .prefixes
            .take()
            .ok_or(ConsumerEncodingFault::PriorFault)?
            .split();
        Ok(PrefixData {
            bytes: data::ObservedBytes::adopt_prefix(bytes, permission),
            output: RefCell::new(Some(output)),
        })
    }
}
