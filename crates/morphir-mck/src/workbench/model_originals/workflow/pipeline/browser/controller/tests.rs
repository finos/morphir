//! Physical Chromium/controller controls, not application/source qualification.
use super::controller::{
    AcquiredTarget, BrowserController, ControllerCommand, ControllerFault, ControllerFinish,
    ControllerProgress, ControllerReply, RootState, parse_reply,
};
use crate::transport::Limits;
use std::{
    future::{Future, poll_fn},
    path::PathBuf,
    pin::pin,
    sync::atomic::AtomicBool,
    task::{Context, Poll, Waker},
    time::{Duration, Instant},
};
fn supplied(name: &str) -> PathBuf {
    let path =
        PathBuf::from(std::env::var_os(name).unwrap_or_else(|| panic!("explicit {name} required")));
    assert!(path.is_absolute(), "explicit absolute target required");
    path
}
fn target(root: &std::path::Path) -> AcquiredTarget {
    AcquiredTarget::acquire(
        supplied("MORPHIR_MCK_BROWSER_CHROMIUM"),
        supplied("MORPHIR_MCK_BROWSER_NODE"),
        supplied("MORPHIR_MCK_BROWSER_PLAYWRIGHT"),
        root.to_path_buf(),
    )
    .expect("actual executable/package/directory acquisition required")
}
fn limits() -> Limits {
    Limits {
        session_timeout: Duration::from_secs(30),
        request_timeout: Duration::from_secs(10),
        max_frame: 16384,
        stderr_capture: 16384,
        ..Limits::DEFAULT
    }
}
struct Actual(Option<BrowserController>);
impl Actual {
    fn owner(&mut self) -> &mut BrowserController {
        self.0.as_mut().unwrap()
    }
    fn finish(mut self) -> super::controller::ControllerOutcome {
        self.owner().request_shutdown();
        let end = Instant::now() + Duration::from_secs(15);
        while !self.owner().poll_cleanup() {
            assert!(
                Instant::now() < end,
                "actual roots/readers cleanup did not finish"
            );
            std::thread::sleep(Duration::from_millis(1));
        }
        match self.0.take().unwrap().into_finished() {
            ControllerFinish::Finished(outcome) => outcome,
            ControllerFinish::Pending(owner) => {
                self.0 = Some(owner);
                panic!("actual controller remains pending")
            }
        }
    }
}
impl Drop for Actual {
    fn drop(&mut self) {
        if let Some(owner) = self.0.as_mut() {
            owner.request_shutdown();
            let end = Instant::now() + Duration::from_secs(15);
            while !owner.poll_cleanup() && Instant::now() < end {
                std::thread::sleep(Duration::from_millis(1));
            }
        }
    }
}
fn next(actual: &mut Actual) -> Result<ControllerProgress, ControllerFault> {
    let interrupted = AtomicBool::new(false);
    loop {
        match actual.owner().poll(&interrupted)? {
            ControllerProgress::Pending => std::thread::sleep(Duration::from_millis(1)),
            other => return Ok(other),
        }
    }
}
#[test]
#[ignore = "requires explicit acquired Chromium/Node/Playwright inputs; required physical qualification command"]
fn browser_controller_c01_real_chromium_attach_page_disconnect_and_separate_root_cleanup() {
    let directory = tempfile::tempdir().unwrap();
    let end = Instant::now() + limits().session_timeout;
    let mut actual = Actual(Some(
        BrowserController::launch(target(directory.path()), limits(), end).unwrap(),
    ));
    let attached = next(&mut actual);
    let page_send = actual.owner().begin(ControllerCommand::CreateProbePage);
    let page = next(&mut actual);
    let close_send = actual
        .owner()
        .begin(ControllerCommand::ClosePageContextAndDisconnect);
    let close = next(&mut actual);
    let driver = next(&mut actual);
    let chromium = actual.owner().chromium_state();
    let retained_end = actual.owner().end();
    let outcome = actual.finish();
    assert_eq!(
        attached,
        Ok(ControllerProgress::Reply(ControllerReply::Attached))
    );
    assert_eq!(page_send, Ok(()));
    assert_eq!(
        page,
        Ok(ControllerProgress::Reply(ControllerReply::ProbePageCreated))
    );
    assert_eq!(close_send, Ok(()));
    assert_eq!(
        close,
        Ok(ControllerProgress::Reply(ControllerReply::Disconnected))
    );
    assert_eq!(driver, Ok(ControllerProgress::DriverJoined));
    assert!(
        matches!(chromium, RootState::Running(_)),
        "driver disconnect is not Chromium termination"
    );
    assert_eq!(retained_end, end);
    assert_eq!(outcome.driver().unwrap().process().status().code(), Some(0));
    assert!(outcome.driver().unwrap().first_fault().is_none());
    assert!(outcome.chromium().first_fault().is_none());
    assert!(outcome.first_fault().is_none());
}
#[test]
#[ignore = "requires explicit acquired Chromium/Node/Playwright inputs; required physical qualification command"]
fn browser_controller_c02_borrow_cancel_and_real_driver_interruption_keep_same_chromium_end() {
    let directory = tempfile::tempdir().unwrap();
    let end = Instant::now() + limits().session_timeout;
    let mut actual = Actual(Some(
        BrowserController::launch(target(directory.path()), limits(), end).unwrap(),
    ));
    let attached = next(&mut actual);
    let send = actual.owner().begin(ControllerCommand::CreateProbePage);
    let page = next(&mut actual);
    let ids = actual.owner().ids();
    let pending = {
        let owner = actual.owner();
        let interrupted = AtomicBool::new(false);
        let mut wait = pin!(poll_fn(|_| match owner.poll(&interrupted) {
            Ok(ControllerProgress::Pending) => Poll::<Result<(), ControllerFault>>::Pending,
            Err(fault) => Poll::Ready(Err(fault)),
            _ => Poll::Ready(Ok(())),
        }));
        wait.as_mut()
            .poll(&mut Context::from_waker(Waker::noop()))
            .is_pending()
    };
    let same_ids = actual.owner().ids();
    let same_end = actual.owner().end();
    actual.owner().request_driver_termination();
    let interrupted = next(&mut actual);
    let chromium = actual.owner().chromium_state();
    let outcome = actual.finish();
    assert_eq!(
        attached,
        Ok(ControllerProgress::Reply(ControllerReply::Attached))
    );
    assert_eq!(send, Ok(()));
    assert_eq!(
        page,
        Ok(ControllerProgress::Reply(ControllerReply::ProbePageCreated))
    );
    assert!(pending);
    assert_eq!(same_ids, ids);
    assert_eq!(same_end, end);
    assert_eq!(interrupted, Err(ControllerFault::DriverExited));
    assert!(matches!(chromium, RootState::Running(_)));
    assert!(outcome.driver().is_some());
    assert_eq!(outcome.first_fault(), Some(&ControllerFault::DriverExited));
}
#[test]
#[ignore = "requires explicit acquired Chromium/Node/Playwright inputs; required physical qualification command"]
fn browser_controller_c03_duplicate_command_refuses_then_both_actual_roots_join() {
    let directory = tempfile::tempdir().unwrap();
    let end = Instant::now() + limits().session_timeout;
    let mut actual = Actual(Some(
        BrowserController::launch(target(directory.path()), limits(), end).unwrap(),
    ));
    let attached = next(&mut actual);
    let sent = actual.owner().begin(ControllerCommand::CreateProbePage);
    let page = next(&mut actual);
    let refusal = actual.owner().begin(ControllerCommand::CreateProbePage);
    let retry = actual
        .owner()
        .begin(ControllerCommand::ClosePageContextAndDisconnect);
    let outcome = actual.finish();
    assert_eq!(
        attached,
        Ok(ControllerProgress::Reply(ControllerReply::Attached))
    );
    assert_eq!(sent, Ok(()));
    assert_eq!(
        page,
        Ok(ControllerProgress::Reply(ControllerReply::ProbePageCreated))
    );
    assert_eq!(refusal, Err(ControllerFault::Order));
    assert_eq!(retry, refusal);
    assert_eq!(outcome.first_fault(), Some(&ControllerFault::Order));
    assert!(outcome.driver().is_some());
}
#[test]
fn browser_controller_c04_closed_literal_reply_grammar_has_no_generic_payload_or_authority() {
    assert_eq!(parse_reply(b"attached\n"), Ok(ControllerReply::Attached));
    assert_eq!(
        parse_reply(b"1 page-created\n"),
        Ok(ControllerReply::ProbePageCreated)
    );
    assert_eq!(
        parse_reply(b"2 disconnected\n"),
        Ok(ControllerReply::Disconnected)
    );
    for raw in [
        b"attached".as_slice(),
        b"attached\nextra\n",
        b"0 page-created\n",
        b"1 arbitrary-eval\n",
        b"2 disconnected\r\n",
    ] {
        assert_eq!(parse_reply(raw), Err(ControllerFault::Shape));
    }
}
