//! Physical post-exit census DATA. Completion is explicit after the actual walk.
use super::collection::grow;
use super::*;
use crate::workbench::model_originals::workflow::{
    ContentSha256, Items, Natural, installed_measurements as data,
};
use sha2::{Digest, Sha256};
#[derive(Clone, Copy)]
pub enum InstalledSnapshot {
    Destination,
    Scratch,
}
impl InstalledClientRun<'_> {
    pub fn observation_read_buffer(
        &mut self,
        length: usize,
    ) -> Result<Vec<u8>, InstalledAdapterError> {
        let mut buffer = self.vector(length)?;
        buffer.resize(length, 0);
        Ok(buffer)
    }
    pub fn visit_observation_bytes(&mut self, length: usize) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        self.charge_storage(length, 0)?;
        let result = self.decode.bytes(length);
        self.decoded(result)
    }
    pub fn observation_path(&mut self, path: &str) -> Result<SourcePath, InstalledAdapterError> {
        self.source_path(path)
    }
    pub fn observation_text<const MIN: usize, const MAX: usize>(
        &mut self,
        raw: &str,
    ) -> Result<Text<MIN, MAX>, InstalledAdapterError> {
        self.owned_text(raw)
    }
    fn snapshot(
        &mut self,
        target: InstalledSnapshot,
    ) -> Result<&mut data::PostExitSnapshot, InstalledAdapterError> {
        match target {
            InstalledSnapshot::Destination => self.destination.as_mut(),
            InstalledSnapshot::Scratch => self.scratch.as_mut(),
        }
        .ok_or(InstalledAdapterError::ObservationIncomplete)
    }
    pub(super) fn source_path(&mut self, path: &str) -> Result<SourcePath, InstalledAdapterError> {
        self.reserve_storage(path.len())?;
        self.decode.bytes(path.len()).map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        SourcePath::new(path).map_err(|_| InstalledAdapterError::ObservationIncomplete)
    }
    pub(super) fn owned_text<const MIN: usize, const MAX: usize>(
        &mut self,
        raw: &str,
    ) -> Result<Text<MIN, MAX>, InstalledAdapterError> {
        self.work_ready()?;
        let text = super::super::observation::prepare_text_copy(
            self.receiving,
            self.comparison,
            ObservationBufferRole::CensusMetadata,
            raw,
        )
        .and_then(|ticket| ticket.retain_text())
        .map_err(|_| InstalledAdapterError::ObservationIncomplete)?
        .into_string();
        self.visit_observation_bytes(text.len())?;
        Text::from_owned(text).map_err(|_| {
            self.attempt.fail(RunFault::Decode(
                crate::workbench::model_originals::workflow::DecodeError::Shape(
                    "observation text representation",
                ),
            ));
            InstalledAdapterError::ObservationIncomplete
        })
    }
    pub fn begin_snapshot(
        &mut self,
        target: InstalledSnapshot,
        after_action: usize,
        root: &str,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        let root = self.owned_text(root)?;
        let snapshot = data::PostExitSnapshot {
            after_action: Natural(after_action as u64),
            root,
            coverage: data::SnapshotCoverage::Incomplete,
            raw_entries: Items(Vec::new()),
            files: Items(Vec::new()),
        };
        let slot = match target {
            InstalledSnapshot::Destination => &mut self.destination,
            InstalledSnapshot::Scratch => &mut self.scratch,
        };
        if slot.is_some() {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        *slot = Some(snapshot);
        Ok(())
    }
    pub fn record_snapshot_directory(
        &mut self,
        target: InstalledSnapshot,
        path: &str,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        let record = self
            .receiving
            .prepare_record(ObservationRecordRole::SnapshotEntry)
            .map(|permission| {
                permission.issue();
            })
            .map_err(|error| *error);
        if let Err(error) = record {
            return Err(self.observation_failure(error));
        }
        let path = self.source_path(path)?;
        self.decode.slots(1).map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        let snapshot = match target {
            InstalledSnapshot::Destination => self.destination.as_mut(),
            InstalledSnapshot::Scratch => self.scratch.as_mut(),
        }
        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        grow(self.receiving, &mut snapshot.raw_entries.0, 1).map_err(|error| {
            self.attempt.fail(RunFault::InstalledObservation(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        snapshot
            .raw_entries
            .0
            .push(data::CensusEntry::PhysicalDirectory { path });
        Ok(())
    }
    pub fn record_snapshot_file(
        &mut self,
        target: InstalledSnapshot,
        path: &str,
        raw: &[u8],
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        let record = self
            .receiving
            .prepare_record(ObservationRecordRole::SnapshotEntry)
            .map(|permission| {
                permission.issue();
            })
            .map_err(|error| *error);
        if let Err(error) = record {
            return Err(self.observation_failure(error));
        }
        let entry_path = self.source_path(path)?;
        let summary_path = self.source_path(path)?;
        self.charge_storage(raw.len(), 0)?;
        let sha256 = ContentSha256::new(Sha256::digest(raw).into());
        let bytes = self.literal_bytes(
            match target {
                InstalledSnapshot::Destination => ObservationBufferRole::DestinationContent,
                InstalledSnapshot::Scratch => ObservationBufferRole::ScratchContent,
            },
            raw,
        )?;
        self.decode.slots(2).map_err(|error| {
            self.attempt.fail(RunFault::Decode(error));
            InstalledAdapterError::ObservationIncomplete
        })?;
        let snapshot = match target {
            InstalledSnapshot::Destination => self.destination.as_mut(),
            InstalledSnapshot::Scratch => self.scratch.as_mut(),
        }
        .ok_or(InstalledAdapterError::ObservationIncomplete)?;
        for result in [
            grow(self.receiving, &mut snapshot.raw_entries.0, 1),
            grow(self.receiving, &mut snapshot.files.0, 1),
        ] {
            result.map_err(|error| {
                self.attempt.fail(RunFault::InstalledObservation(error));
                InstalledAdapterError::ObservationIncomplete
            })?;
        }
        snapshot.raw_entries.0.push(data::CensusEntry::File {
            path: entry_path,
            bytes,
        });
        snapshot.files.0.push(data::FileSummary {
            path: summary_path,
            byte_length: Natural(raw.len() as u64),
            sha256,
        });
        Ok(())
    }
    pub fn complete_snapshot(
        &mut self,
        target: InstalledSnapshot,
    ) -> Result<(), InstalledAdapterError> {
        self.work_ready()?;
        self.snapshot(target)?.coverage = data::SnapshotCoverage::Complete;
        Ok(())
    }
    pub fn published_path(&mut self) -> Result<&str, InstalledAdapterError> {
        self.work_ready()?;
        let value = self
            .collected
            .claim(2, &["published"], self.decode)
            .map_err(|error| {
                self.attempt.fail(RunFault::Decode(error));
                InstalledAdapterError::ObservationIncomplete
            })?;
        let Some(crate::json::strict::Document::Array(paths)) = value else {
            return Err(InstalledAdapterError::ObservationIncomplete);
        };
        paths
            .first()
            .and_then(data::text)
            .ok_or(InstalledAdapterError::ObservationIncomplete)
    }
}
