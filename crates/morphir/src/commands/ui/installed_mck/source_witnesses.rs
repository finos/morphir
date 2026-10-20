//! SDK identities issued from the actual compiled fixture before any reads.
use super::super::model_originals::observation::HostSourceSnapshot;
use super::*;
use morphir_common::config::observation::FileReadWitness;
use morphir_mck::workbench::model_originals::native::data::{FileRole, ObservedCount, ReadCounts};
use std::path::Path;

struct FileWitness<'source> {
    role: FileRole,
    path: &'source data::SourcePath,
    witness: FileReadWitness,
}
pub(super) struct Witnesses<'source> {
    files: [FileWitness<'source>; 3],
}
impl<'source> Witnesses<'source> {
    pub(super) fn register(
        run: &mut InstalledClientRun<'source>,
        scope: &HostSourceObservationScope,
        held: &Dir,
    ) -> Result<Self, InstalledAdapterError> {
        let fixture = run.fixture();
        let mut paths = fixture.witnesses();
        let mut register = || {
            let (role, path) = paths
                .next()
                .ok_or(InstalledAdapterError::ObservationIncomplete)?;
            // Fund the actual native component scan before SDK registration.
            // The SDK's SAME explicit files limit bounds identity retention.
            run.visit_observation_bytes(path.as_str().len())?;
            let witness = scope
                .source_scope()
                .register_file(held, Path::new(path.as_str()))
                .map_err(incomplete)?;
            Ok::<_, InstalledAdapterError>(FileWitness {
                role,
                path,
                witness,
            })
        };
        let files = [register()?, register()?, register()?];
        if paths.next().is_some() {
            return Err(InstalledAdapterError::ObservationIncomplete);
        }
        Ok(Self { files })
    }
    pub(super) fn measurements(
        self,
        run: &mut InstalledClientRun<'_>,
        snapshot: &HostSourceSnapshot,
    ) -> Result<data::SourceMeasurements, InstalledAdapterError> {
        snapshot.require_source_complete().map_err(incomplete)?;
        let [record, primary, sentinel] = self.files.map(|file| {
            snapshot
                .reads()
                .counts_for(&file.witness)
                .map(|counts| {
                    (
                        file.role,
                        file.path,
                        ReadCounts {
                            attempts: ObservedCount(counts.content_attempts()),
                            read_calls: ObservedCount(counts.read_calls()),
                            returned_bytes: ObservedCount(counts.returned_bytes()),
                        },
                    )
                })
                .map_err(incomplete)
        });
        let files = run.retain_source_files([record?, primary?, sentinel?].into_iter())?;
        Ok(data::SourceMeasurements::SealedComplete {
            counts: measurements::prefix(snapshot.reads()),
            files,
        })
    }
}
