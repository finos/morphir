//! Typed factual builders for the real adapter. Values never issue authority.
use super::*;
use crate::workbench::model_originals::workflow::{
    ContentSha256, Items, Natural, installed_measurements as model,
};
use model::implementation::*;
use sha2::{Digest, Sha256};
impl InstalledClientRun<'_> {
    pub fn observation_literal_bytes(
        &mut self,
        role: ObservationBufferRole,
        raw: &[u8],
    ) -> Result<model::ObservedBytes, InstalledAdapterError> {
        self.work_ready()?;
        self.literal_bytes(role, raw)
    }
    pub fn observation_package_file(
        &mut self,
        entries: &mut Vec<PackageFile>,
        path: &str,
        mode: FileMode,
        length: u64,
        sha256: [u8; 32],
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        let path = self.observation_path(path)?;
        self.decode.slots(1).map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        super::collection::grow(self.receiving, entries, 1)
            .map_err(|error| self.observation_failure(error))?;
        entries.push(PackageFile {
            path,
            mode,
            byte_length: Natural(length),
            sha256: ContentSha256::new(sha256),
        });
        Ok(())
    }
    pub fn observation_source_file(
        &mut self,
        entries: &mut Vec<SourceEntry>,
        path: &str,
        mode: FileMode,
        length: u64,
        sha256: [u8; 32],
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        let path = self.observation_path(path)?;
        self.decode.slots(1).map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        super::collection::grow(self.receiving, entries, 1)
            .map_err(|error| self.observation_failure(error))?;
        entries.push(SourceEntry::File {
            path,
            mode,
            byte_length: Natural(length),
            sha256: ContentSha256::new(sha256),
        });
        Ok(())
    }
    pub fn observation_source_link(
        &mut self,
        entries: &mut Vec<SourceEntry>,
        path: &str,
        target: &[u8],
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        let path = self.observation_path(path)?;
        self.visit_observation_bytes(target.len())?;
        let digest = Sha256::digest(target).into();
        let target_bytes = self.literal_bytes(ObservationBufferRole::AssociationContent, target)?;
        self.decode.slots(1).map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        super::collection::grow(self.receiving, entries, 1)
            .map_err(|error| self.observation_failure(error))?;
        entries.push(SourceEntry::SymlinkLiteral {
            path,
            target_bytes,
            byte_length: Natural(target.len() as u64),
            sha256: ContentSha256::new(digest),
        });
        Ok(())
    }
    fn descriptor_digest<'a>(
        &mut self,
        entries: impl Iterator<Item = Descriptor<'a>>,
    ) -> Result<ContentSha256, InstalledAdapterError> {
        self.work_ready()?;
        let mut hash = Sha256::new();
        for Descriptor {
            kind,
            mode,
            path,
            length,
            digest,
        } in entries
        {
            self.visit_observation_bytes(
                path.len()
                    .checked_add(50)
                    .ok_or(InstalledAdapterError::ObservationIncomplete)?,
            )?;
            hash.update([kind, mode]);
            hash.update((path.len() as u64).to_be_bytes());
            hash.update(path.as_bytes());
            hash.update(length.to_be_bytes());
            hash.update(digest);
        }
        Ok(ContentSha256::new(hash.finalize().into()))
    }
    pub fn package_census_digest(
        &mut self,
        entries: &[PackageFile],
    ) -> Result<ContentSha256, InstalledAdapterError> {
        self.descriptor_digest(entries.iter().map(PackageFile::descriptor))
    }
    pub fn source_census_digest(
        &mut self,
        entries: &[SourceEntry],
    ) -> Result<ContentSha256, InstalledAdapterError> {
        self.descriptor_digest(entries.iter().map(SourceEntry::descriptor))
    }
    pub fn sort_package_entries(
        &mut self,
        entries: &mut [PackageFile],
    ) -> Result<(), InstalledAdapterError> {
        // Fallible heapsort uses no extra allocation; compare whole actual key
        // spans before each comparison, rather than an unbudgeted comparator.
        fn sift(
            run: &mut InstalledClientRun<'_>,
            rows: &mut [PackageFile],
            mut root: usize,
        ) -> Result<(), InstalledAdapterError> {
            while let Some(mut child) = root
                .checked_mul(2)
                .and_then(|n| n.checked_add(1))
                .filter(|n| *n < rows.len())
            {
                if child + 1 < rows.len() {
                    run.visit_observation_bytes(
                        rows[child]
                            .path
                            .as_str()
                            .len()
                            .saturating_add(rows[child + 1].path.as_str().len()),
                    )?;
                    if rows[child].path.as_str() < rows[child + 1].path.as_str() {
                        child += 1
                    }
                }
                run.visit_observation_bytes(
                    rows[root]
                        .path
                        .as_str()
                        .len()
                        .saturating_add(rows[child].path.as_str().len()),
                )?;
                if rows[root].path.as_str() >= rows[child].path.as_str() {
                    break;
                }
                rows.swap(root, child);
                root = child;
            }
            Ok(())
        }
        for root in (0..entries.len() / 2).rev() {
            sift(self, entries, root)?;
        }
        for end in (1..entries.len()).rev() {
            entries.swap(0, end);
            sift(self, &mut entries[..end], 0)?;
        }
        Ok(())
    }
    pub fn take_metadata_tools(&mut self) -> Result<Vec<ToolProcess>, InstalledAdapterError> {
        self.work_ready()?;
        let tools = std::mem::take(&mut self.collected.tools);
        let mut result = self.vector(tools.len())?;
        for tool in tools {
            if !self.revoker.matches(&tool.description.invocation) {
                self.attempt.fail(RunFault::Installed(
                    InstalledAdapterError::ObservationIncomplete,
                ));
                return Err(InstalledAdapterError::ObservationIncomplete);
            }
            let query = match tool.description.purpose {
                InstalledProcessPurpose::Metadata(query) => match query {
                    InstalledMetadataQuery::Revision => GitQuery::Revision,
                    InstalledMetadataQuery::TrackedInventory => GitQuery::TrackedInventory,
                    InstalledMetadataQuery::TrackedStatus => GitQuery::TrackedStatus,
                },
                _ => return Err(InstalledAdapterError::ObservationIncomplete),
            };
            let program = self.observation_operand(&tool.description.program)?;
            let directory = self.observation_operand(&tool.description.directory)?;
            let mut arguments = self.vector(tool.description.arguments.len())?;
            for argument in &tool.description.arguments {
                arguments.push(self.observation_operand(argument)?);
            }
            let stdout =
                self.literal_bytes(ObservationBufferRole::StdoutPrefix, tool.outcome.stdout())?;
            let stderr =
                self.literal_bytes(ObservationBufferRole::StderrPrefix, tool.outcome.stderr())?;
            result.push(ToolProcess{process_ordinal:Natural(tool.description.ordinal),tool:GitTool,query,program,directory,arguments:Items(arguments),completion:process_completion(&tool.outcome),stdout,stderr,stderr_truncated:model::MeasuredBool::live(tool.outcome.stderr_truncated()),descendants:match tool.outcome.descendants(){crate::transport::process::DescendantEvidence::Unobserved=>model::DescendantCoverage::Unobserved,crate::transport::process::DescendantEvidence::TerminationRequestedUnverified=>model::DescendantCoverage::TerminationRequestedUnverified}});
        }
        Ok(result)
    }
    pub fn finish_consumer_measurements(
        mut self,
        published_relative_root: &str,
        source: data::SourceMeasurements,
        workers: data::WorkerMeasurements,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.work_ready()?;
        if self.collected.consumer.is_none()
            || !matches!(
                self.collected
                    .consumer_context
                    .as_ref()
                    .map(|context| &context.implementation),
                Some(ImplementationObservation::Observed { .. })
            )
            || self.destination.is_none()
            || self.scratch.is_none()
        {
            self.attempt.fail(RunFault::Installed(
                InstalledAdapterError::ObservationIncomplete,
            ));
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        let relative = self.observation_path(published_relative_root)?;
        // All fallible prerequisites are checked before consuming the actual
        // implementation, selection, host prefix or process collection.
        let context = self
            .collected
            .consumer_context
            .take()
            .expect("validated retained context");
        let host = model::HostMeasurement {
            association: model::InvocationAssociation,
            selection: context.selection,
            events: Items(std::mem::take(&mut self.collected.events)),
            source,
            workers,
        };
        let destination = self.destination.take().expect("validated destination");
        let scratch = self.scratch.take().expect("validated scratch");
        self.collected
            .finish(
                context.implementation,
                host,
                destination,
                relative,
                scratch,
                self.decode,
            )
            .map_err(|error| {
                self.attempt.fail(RunFault::Decode(error));
                InstalledAdapterError::ObservationIncomplete
            })
    }
    pub fn finish_measurements(
        mut self,
        implementation: ImplementationObservation,
        published_relative_root: &str,
        source: data::SourceMeasurements,
        workers: data::WorkerMeasurements,
    ) -> Result<InstalledClientMeasurements, InstalledAdapterError> {
        self.work_ready()?;
        if matches!(
            self.revoker.consumer_selection,
            crate::workbench::configuration::ConsumerObservationSelection::OperationPort(_)
        ) && self.collected.consumer.is_none()
        {
            self.attempt.fail(RunFault::Installed(
                InstalledAdapterError::ObservationIncomplete,
            ));
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        if !matches!(implementation, ImplementationObservation::Observed { .. }) {
            self.attempt
                .fail(RunFault::Record(WorkflowRecordError::Observation(
                    observation_check::ObservationError::InstalledClient(
                        observation_check::InstalledClientFault::ImplementationMissing,
                    ),
                )));
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        let relative = self.observation_path(published_relative_root)?;
        let selected =
            super::selections::runtime_selection(self.collected, self.decode, self.receiving)
                .map_err(|error| {
                    self.attempt.fail(RunFault::Decode(error));
                    InstalledAdapterError::ObservationIncomplete
                })?;
        let host = model::HostMeasurement {
            association: model::InvocationAssociation,
            selection: selected,
            events: Items(std::mem::take(&mut self.collected.events)),
            source,
            workers,
        };
        let destination = self
            .destination
            .take()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        let scratch = self
            .scratch
            .take()
            .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        let result = self.collected.finish(
            implementation,
            host,
            destination,
            relative,
            scratch,
            self.decode,
        );
        result.map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })
    }
}
pub(super) fn process_completion(
    outcome: &crate::transport::process::ProcessOutcome,
) -> model::DirectProcessCompletion {
    model::DirectProcessCompletion::Finished {
        exit: match outcome.status().code() {
            Some(code) if code >= 0 => model::ProcessExit::Code {
                value: Natural(code as u64),
            },
            _ => model::ProcessExit::Other {},
        },
    }
}
