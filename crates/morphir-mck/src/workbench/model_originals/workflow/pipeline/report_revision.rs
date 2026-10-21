//! Report-only revisions. Corpus, operations and negotiated protocol stay draft30.
use super::raw::VERSION;
use crate::workbench::configuration::ConsumerObservationSelection;

const CONSUMER: &str = "0.1.0-draft.31";
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum ReportRevision {
    Legacy30,
    Consumer31,
}
impl ReportRevision {
    pub(super) fn parse(text: &str) -> Result<Self, &'static str> {
        // Exact supported spellings imply canonical form after library parsing.
        // This does not widen the independently validated corpus/protocol version.
        semver::Version::parse(text).map_err(|_| "report version")?;
        match text {
            VERSION => Ok(Self::Legacy30),
            CONSUMER => Ok(Self::Consumer31),
            _ => Err("unsupported report version"),
        }
    }
    pub(super) fn selected(selection: ConsumerObservationSelection) -> Self {
        match selection {
            ConsumerObservationSelection::Disabled => Self::Legacy30,
            ConsumerObservationSelection::OperationPort(_) => Self::Consumer31,
        }
    }
    pub(super) fn text(self) -> &'static str {
        match self {
            Self::Legacy30 => VERSION,
            Self::Consumer31 => CONSUMER,
        }
    }
}
