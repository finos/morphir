//! Native/physical owners staged before listener installation. Staging is
//! ownership preparation, never source authority or a browser reply.
use super::*;
use morphir_mck::workbench::{
    BrowserControllerBusinessCredit, BrowserControllerLaunchFailure, BrowserFixedController,
    BrowserMaterializedController,
};

pub(super) struct SelectedSourceControllerPrepared<'a> {
    pub(super) native: SelectedSourcePrepared<'a>,
    pub(super) materialized: BrowserMaterializedController,
    pub(super) listener_credit: BrowserControllerBusinessCredit,
}

pub(super) struct SelectedSourceControllerPreparationFailure<'a> {
    pub(super) native: SelectedSourcePrepared<'a>,
    pub(super) materialized: BrowserMaterializedController,
    pub(super) cause: BrowserActionIssueError,
}

pub(super) struct SelectedSourceControllerLaunched<'a> {
    pub(super) native: SelectedSourcePrepared<'a>,
    pub(super) listener_credit: BrowserControllerBusinessCredit,
    pub(super) controller: BrowserFixedController,
}

pub(super) enum SelectedSourceControllerLaunchFailure<'a> {
    BeforeSpawn {
        staged: SelectedSourceControllerPrepared<'a>,
        cause: SelectedSourceStartFault,
    },
    Physical {
        native: SelectedSourcePrepared<'a>,
        listener_credit: BrowserControllerBusinessCredit,
        controller: BrowserControllerLaunchFailure,
    },
}

impl<'a> SelectedSourcePrepared<'a> {
    /// Take only this materialized owner's already-funded allowance. The SDK
    /// still validates the actual source/host relation before physical launch.
    /// Every visible returned wrapper was paid before runtime acquisition.
    pub(super) fn prepare_controller_launch(
        self,
        mut materialized: BrowserMaterializedController,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<SelectedSourceControllerPrepared<'a>, SelectedSourceControllerPreparationFailure<'a>>
    {
        match materialized.listener_start_credit(loans) {
            Ok(listener_credit) => Ok(SelectedSourceControllerPrepared {
                native: self,
                materialized,
                listener_credit,
            }),
            Err(cause) => Err(SelectedSourceControllerPreparationFailure {
                native: self,
                materialized,
                cause,
            }),
        }
    }
}

impl<'a> SelectedSourceControllerPrepared<'a> {
    /// The only physical launch from this stage is the maintained controller's
    /// initial about:blank child. No listener, Node driver or Page is started.
    pub(super) fn launch_controller(
        self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<SelectedSourceControllerLaunched<'a>, SelectedSourceControllerLaunchFailure<'a>>
    {
        let native_check = (|| {
            let owner = &self.native.launch.owner;
            let _first = SelectedSourceHost::active_native_first(&owner.host.state)?;
            owner.check_prepared_listener(owner.application.end)
        })();
        if let Err(cause) = native_check {
            return Err(SelectedSourceControllerLaunchFailure::BeforeSpawn {
                staged: self,
                cause,
            });
        }
        // Bound means the sole native listener future has never been polled,
        // so there are no native peer writers during this initial launch.
        // Release native-first before the controller re-enters source/loans;
        // holding it here would invert the final source→journal→native order.
        let Self {
            native,
            materialized,
            listener_credit,
        } = self;
        match materialized.launch(
            native.launch.owner.host.launch_url(),
            &native.launch.opening,
            loans,
        ) {
            Ok(controller) => Ok(SelectedSourceControllerLaunched {
                native,
                listener_credit,
                controller,
            }),
            Err(controller) => Err(SelectedSourceControllerLaunchFailure::Physical {
                native,
                listener_credit,
                controller,
            }),
        }
    }
}
