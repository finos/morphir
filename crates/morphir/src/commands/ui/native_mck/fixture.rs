//! Materialize only engine-issued recipes; this module supplies no oracle.
use std::{collections::BTreeMap, io::Write, path::PathBuf};

use morphir_mck::workbench::model_originals::native::{
    NativeAdapterError, NativeOriginalNode, NativeOriginalRun, NativeOutputOverride,
};

pub(super) struct Fixture {
    _temporary: tempfile::TempDir,
    pub root: PathBuf,
    pub output: crate::commands::out_context::OutOverrides,
}

impl Fixture {
    pub fn materialize(
        run: &mut NativeOriginalRun<'_>,
        check: impl Fn() -> Result<(), NativeAdapterError>,
    ) -> Result<Self, NativeAdapterError> {
        let fixture = run.fixture();
        if fixture.records().len() != 0 || fixture.guests().len() != 0 {
            return Err(NativeAdapterError::UnsupportedAction);
        }
        let temporary = tempfile::tempdir().map_err(|_| NativeAdapterError::Fixture)?;
        let base = temporary
            .path()
            .canonicalize()
            .map_err(|_| NativeAdapterError::Fixture)?;
        let mut grants = BTreeMap::new();
        for (index, grant) in fixture.grants().enumerate() {
            check()?;
            // Aliases select this local map, never an ambient filesystem path.
            let path = base.join(format!("grant-{index}"));
            std::fs::create_dir(&path).map_err(|_| NativeAdapterError::Fixture)?;
            for node in grant.nodes() {
                check()?;
                match node {
                    NativeOriginalNode::File {
                        path: relative,
                        bytes,
                    } => {
                        let path = path.join(relative.as_str());
                        if let Some(parent) = path.parent() {
                            std::fs::create_dir_all(parent)
                                .map_err(|_| NativeAdapterError::Fixture)?;
                        }
                        let expanded = run.materialize_fixture_bytes(bytes)?;
                        let mut file =
                            std::fs::File::create(path).map_err(|_| NativeAdapterError::Fixture)?;
                        let mut offset = 0;
                        let mut window = [0u8; 65_536];
                        while offset < expanded.byte_length() {
                            check()?;
                            let count = window.len().min(expanded.byte_length() - offset);
                            expanded
                                .fill_window(offset, &mut window[..count])
                                .map_err(|_| NativeAdapterError::Fixture)?;
                            file.write_all(&window[..count])
                                .map_err(|_| NativeAdapterError::Fixture)?;
                            offset += count;
                        }
                    }
                    NativeOriginalNode::Directory { path: relative } => {
                        std::fs::create_dir_all(path.join(relative.as_str()))
                            .map_err(|_| NativeAdapterError::Fixture)?;
                    }
                    NativeOriginalNode::Symlink { .. }
                    | NativeOriginalNode::Fifo { .. }
                    | NativeOriginalNode::Socket { .. }
                    | NativeOriginalNode::RawNameFile { .. }
                    | NativeOriginalNode::EntrySeries { .. } => {
                        return Err(NativeAdapterError::UnsupportedAction);
                    }
                }
            }
            grants.insert(grant.alias().clone(), path);
        }
        let startup = fixture.startup();
        let root = grants
            .get(startup.cwd())
            .cloned()
            .ok_or(NativeAdapterError::Fixture)?;
        let output = match startup.output_override() {
            NativeOutputOverride::None => {
                crate::commands::out_context::OutOverrides::from_process(None)
            }
            NativeOutputOverride::Explicit { grant } => {
                crate::commands::out_context::OutOverrides::from_process(Some(
                    grants
                        .get(grant)
                        .cloned()
                        .ok_or(NativeAdapterError::Fixture)?,
                ))
            }
        };
        let mut providers = fixture.providers();
        let provider = providers.next().ok_or(NativeAdapterError::Fixture)?;
        if providers.next().is_some() || grants.get(provider.grant()) != Some(&root) {
            return Err(NativeAdapterError::UnsupportedAction);
        }
        Ok(Self {
            _temporary: temporary,
            root,
            output,
        })
    }
}
