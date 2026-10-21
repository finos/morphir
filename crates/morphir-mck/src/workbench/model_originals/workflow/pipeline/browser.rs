//! Private browser observation support. No browser execution or source grant.
mod archive_download;
mod inputs;

use super::installed::observation::InstalledObservationOwner;
use super::{PreparationFault, Source, prepared_typed};
use crate::workbench::configuration::{BrowserClient, Configuration, RunConfiguration};
use crate::workbench::model_originals::workflow::reviewed_sources::ReviewedSources;
use inputs::{BorrowedOriginalClients, BrowserOwnerLoans};

#[derive(Debug)]
enum BrowserPreparationFault<E> {
    WrongConfiguration,
    Preparation(PreparationFault<E>),
}
/// Source preparation and input loans only. No browser or artifact authority.
fn prepared_browser_originals<R, E>(
    source: &Source,
    configuration: &RunConfiguration,
    action: impl FnOnce(
        BorrowedOriginalClients<'_, '_, '_, '_, '_>,
        &mut BrowserOwnerLoans<'_>,
    ) -> Result<R, E>,
) -> Result<R, BrowserPreparationFault<E>> {
    let Configuration::BrowserOriginals {
        checker,
        receiving,
        client: BrowserClient::Chromium,
    } = &configuration.mode
    else {
        return Err(BrowserPreparationFault::WrongConfiguration);
    };
    // One storage-domain owner spans every input; it is not a CLI invocation.
    let mut receiving = InstalledObservationOwner::new(receiving);
    prepared_typed(
        source,
        checker,
        ReviewedSources::selected(),
        |compiled, owners| {
            action(
                BorrowedOriginalClients::new(compiled),
                &mut BrowserOwnerLoans::new(owners, &mut receiving),
            )
        },
    )
    .map_err(BrowserPreparationFault::Preparation)
}

#[cfg(test)]
mod privacy_probe;
