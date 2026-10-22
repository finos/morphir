//! Native listener effects under the genuine SDK. No Page or source0 completion.
use super::super::tests::with_actual_selected_launch;
use super::*;
use crate::commands::ui::server::controlled_originals::{
    ControlledHostFault, ControlledHostFinish, ControlledHostJoined, ListenerOwner,
};

#[test]
#[ignore = "requires explicit exact77 selected image; listener only, no Chrome"]
fn native_selected_listener_start_01_same_host_starts_and_physically_joins() {
    with_actual_selected_launch(
        std::time::Duration::from_secs(30),
        |launch, _application, runtime, loans| {
            let pointer = Arc::as_ptr(&launch.owner.host.state);
            let (fault, owner, opening) =
                match runtime.block_on(async { launch.start_listener(loans) }) {
                    Ok(SelectedSourceStarted { owner, opening }) => (None, owner, opening),
                    Err(SelectedSourceStartFailure { fault, launch }) => {
                        (Some(fault), launch.owner, launch.opening)
                    }
                };
            let same = Arc::as_ptr(&owner.host.state) == pointer;
            let running = matches!(owner.host.listener, ListenerOwner::Running { .. });
            drop(opening);
            let joined = runtime.block_on(owner.host.finish_joined());
            drop(owner.application);
            assert!(same);
            assert!(running);
            assert!(matches!(
                joined,
                ControlledHostFinish::Joined(ControlledHostJoined::Clean)
            ));
            assert!(fault.is_none(), "genuine prepared listener must start");
        },
    );
}

#[test]
#[ignore = "requires explicit exact77 selected image; native first-cache control only"]
fn native_selected_listener_start_02_prior_native_fault_preserves_bound_listener() {
    with_actual_selected_launch(
        std::time::Duration::from_secs(30),
        |launch, _application, runtime, loans| {
            let pointer = Arc::as_ptr(&launch.owner.host.state);
            // Inject the canonical native first cache, not an OS-failure claim.
            launch.owner.host.state.fault(ControlledHostFault::PeerRead);
            let (fault, owner, opening) =
                match runtime.block_on(async { launch.start_listener(loans) }) {
                    Ok(SelectedSourceStarted { owner, opening }) => (None, owner, opening),
                    Err(SelectedSourceStartFailure { fault, launch }) => {
                        (Some(fault), launch.owner, launch.opening)
                    }
                };
            let same = Arc::as_ptr(&owner.host.state) == pointer;
            let bound = matches!(owner.host.listener, ListenerOwner::Bound(_));
            drop(opening);
            let joined = runtime.block_on(owner.host.finish_joined());
            drop(owner.application);
            assert!(same);
            assert!(bound, "native first fault must prevent actual spawn");
            assert!(matches!(
                joined,
                ControlledHostFinish::Joined(ControlledHostJoined::Fault(
                    ControlledHostFault::PeerRead
                ))
            ));
            assert!(matches!(
                fault,
                Some(SelectedSourceStartFault::Native(
                    ControlledHostFault::PeerRead
                ))
            ));
        },
    );
}

#[test]
#[ignore = "requires explicit exact77 selected image; actual setup refusal only"]
fn native_selected_listener_start_03_missing_runtime_returns_unstarted_owner() {
    with_actual_selected_launch(
        std::time::Duration::from_secs(30),
        |launch, _application, runtime, loans| {
            assert!(tokio::runtime::Handle::try_current().is_err());
            let pointer = Arc::as_ptr(&launch.owner.host.state);
            let (fault, owner, opening) = match launch.start_listener(loans) {
                Ok(SelectedSourceStarted { owner, opening }) => (None, owner, opening),
                Err(SelectedSourceStartFailure { fault, launch }) => {
                    (Some(fault), launch.owner, launch.opening)
                }
            };
            let same = Arc::as_ptr(&owner.host.state) == pointer;
            let bound = matches!(owner.host.listener, ListenerOwner::Bound(_));
            drop(opening);
            let joined = runtime.block_on(owner.host.finish_joined());
            drop(owner.application);
            assert!(same);
            assert!(bound);
            assert!(matches!(
                joined,
                ControlledHostFinish::Joined(ControlledHostJoined::Clean)
            ));
            assert!(matches!(
                fault,
                Some(SelectedSourceStartFault::Native(
                    ControlledHostFault::Listener
                ))
            ));
        },
    );
}

#[test]
#[ignore = "requires explicit exact77 selected image; actual original-end refusal and cleanup"]
fn native_selected_listener_start_04_expired_original_returns_bound_owner_for_cleanup() {
    with_actual_selected_launch(
        std::time::Duration::from_secs(2),
        |launch, _application, runtime, loans| {
            let pointer = Arc::as_ptr(&launch.owner.host.state);
            let end = launch.owner.host.state.end;
            std::thread::sleep(
                end.saturating_duration_since(Instant::now()) + std::time::Duration::from_millis(1),
            );
            let (fault, owner, opening) =
                match runtime.block_on(async { launch.start_listener(loans) }) {
                    Ok(SelectedSourceStarted { owner, opening }) => (None, owner, opening),
                    Err(SelectedSourceStartFailure { fault, launch }) => {
                        (Some(fault), launch.owner, launch.opening)
                    }
                };
            let same = Arc::as_ptr(&owner.host.state) == pointer;
            let bound = matches!(owner.host.listener, ListenerOwner::Bound(_));
            drop(opening);
            let joined = runtime.block_on(owner.host.finish_joined());
            drop(owner.application);
            assert!(same);
            assert!(
                bound,
                "expired business authority must not start the listener"
            );
            assert!(matches!(
                joined,
                ControlledHostFinish::Joined(ControlledHostJoined::Clean)
            ));
            assert!(matches!(
                fault,
                Some(SelectedSourceStartFault::Action(
                    BrowserActionIssueError::Host(
                        morphir_mck::workbench::BrowserHostTranscriptFault::End
                    )
                ))
            ));
        },
    );
}

#[test]
#[ignore = "requires explicit exact77 selected image; actual native lock poison only"]
fn native_selected_listener_start_05_poisoned_native_first_never_starts_listener() {
    poisoned_native_first(None);
}

#[test]
#[ignore = "requires explicit exact77 selected image; earlier native fault survives poison"]
fn native_selected_listener_start_06_poison_preserves_earlier_native_refusal() {
    poisoned_native_first(Some(ControlledHostFault::PeerRead));
}

fn poisoned_native_first(prior: Option<ControlledHostFault>) {
    with_actual_selected_launch(
        std::time::Duration::from_secs(30),
        |launch, _application, runtime, loans| {
            let pointer = Arc::as_ptr(&launch.owner.host.state);
            if let Some(cause) = prior {
                launch.owner.host.state.fault(cause);
            }
            let poisoned = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                let _first = launch
                    .owner
                    .host
                    .state
                    .first
                    .lock()
                    .expect("initially healthy mutex");
                panic!("controlled native first-fault mutex poison");
            }))
            .is_err();
            let (fault, owner, opening) =
                match runtime.block_on(async { launch.start_listener(loans) }) {
                    Ok(SelectedSourceStarted { owner, opening }) => (None, owner, opening),
                    Err(SelectedSourceStartFailure { fault, launch }) => {
                        (Some(fault), launch.owner, launch.opening)
                    }
                };
            let same = Arc::as_ptr(&owner.host.state) == pointer;
            let bound = matches!(owner.host.listener, ListenerOwner::Bound(_));
            drop(opening);
            let joined = runtime.block_on(owner.host.finish_joined());
            drop(owner.application);
            let expected = prior.unwrap_or(ControlledHostFault::Poisoned);
            assert!(poisoned);
            assert!(same);
            assert!(bound, "native poison must refuse before listener spawn");
            assert!(
                matches!(joined, ControlledHostFinish::Joined(ControlledHostJoined::Fault(cause)) if cause == expected)
            );
            assert!(
                matches!(fault, Some(SelectedSourceStartFault::Native(cause)) if cause == expected)
            );
        },
    );
}
