//! Literal native stdio controls. No Chromium, Page or source action is run.
use super::*;
use std::time::Duration;

const COMPLETE: &[u8] = concat!(
    "attached\n",
    "1 document-started\n",
    "2 project-selected\n",
    "3 inspection-pending\n",
    "4 disconnected\n"
)
.as_bytes();

fn literal_driver(root: &Path, bytes: &[u8], limits: Limits) -> InteractiveOutcome {
    let spec = CommandSpec::new(
        PathBuf::from("/bin/sh"),
        vec![
            "-c".into(),
            r#"printf '%s' "$1""#.into(),
            "literal-stdio-control".into(),
            std::str::from_utf8(bytes).unwrap().into(),
        ],
        root.to_owned(),
        vec![],
    )
    .unwrap();
    let mut owner = InteractiveProcess::spawn(
        spec,
        limits,
        FixedCaptureBuffers::new(
            Vec::with_capacity(limits.max_frame),
            Vec::with_capacity(limits.stderr_capture),
        ),
    )
    .unwrap();
    owner.close_stdin();
    let end = Instant::now() + Duration::from_secs(5);
    loop {
        if matches!(
            owner.advance(),
            InteractiveProgress::ExitObserved(_) | InteractiveProgress::Faulted(_)
        ) {
            let _ = owner.request_termination();
            let _ = owner.reap_retained();
        }
        owner.advance();
        match owner.into_finished() {
            InteractiveFinish::Finished(outcome) => return outcome,
            InteractiveFinish::Pending(pending) => owner = pending,
        }
        if Instant::now() >= end {
            let _ = owner.request_termination();
            panic!("literal driver/readers did not finish");
        }
        std::thread::sleep(Duration::from_millis(1));
    }
}

struct LiteralController {
    owner: Option<BrowserController>,
    _directory: tempfile::TempDir,
}
impl LiteralController {
    fn prepare(bytes: &[u8]) -> Self {
        assert_eq!(COMPLETE.len(), SOURCE_STDOUT_BOUND);
        let prefix = SOURCE_STDOUT_BOUND - b"4 disconnected\n".len();
        let actual = Self::prepare_at(bytes, prefix, Conversation::ClosePending);
        assert_eq!(&actual.owner.as_ref().unwrap().capture[..prefix], &COMPLETE[..prefix]);
        actual
    }
    fn prepare_at(bytes: &[u8], prefix: usize, conversation: Conversation) -> Self {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().canonicalize().unwrap();
        let profile = root.join("profile");
        let artifacts = root.join("artifacts");
        fs::create_dir(&profile).unwrap();
        fs::create_dir(&artifacts).unwrap();
        let entry = root.join("literal-held-input");
        fs::write(&entry, b"literal transport fixture, never evaluated").unwrap();
        let limits = Limits {
            max_frame: SOURCE_STDOUT_BOUND,
            stderr_capture: 64,
            ..Limits::DEFAULT
        };
        let driver = literal_driver(&root, bytes, limits);
        assert_eq!(driver.process().stdout().len(), bytes.len().min(SOURCE_STDOUT_BOUND));
        let mut capture = vec![0; SOURCE_STDOUT_BOUND];
        // These earlier bytes are already consumed conversation history. The
        // final frame below still comes from this actual joined stdout owner.
        capture[..prefix].copy_from_slice(&driver.process().stdout()[..prefix]);
        let end = Instant::now() + Duration::from_secs(10);
        let (before, ticks, after, ratio) = clock::sample().unwrap();
        let clock = clock::deadline::export(end, before, ticks, after, ratio).unwrap();
        let spec = CommandSpec::new(
            PathBuf::from("/bin/sleep"),
            vec!["30".into()],
            root.clone(),
            vec![],
        )
        .unwrap();
        let surrogate = OneShotProcess::spawn(spec, limits).unwrap();
        // This private fixture deliberately does not use source acquisition or
        // claim a selected runtime. The held executables are literal processes.
        let target = AcquiredTarget {
            chromium: Executable::acquire(PathBuf::from("/bin/sleep")).unwrap(),
            node: Executable::acquire(PathBuf::from("/bin/sh")).unwrap(),
            entry: entry.clone(),
            _package: File::open(&entry).unwrap(),
            root: root.clone(),
            _root: File::open(&root).unwrap(),
            profile: profile.clone(),
            profile_dir: File::open(&profile).unwrap(),
            artifacts,
            driver: entry,
            _source_owned: None,
        };
        Self {
            owner: Some(BrowserController {
                target,
                variant: ControllerVariant::SourceObserved {
                    launch: ObservedLaunch::parse(
                        "http://127.0.0.1:1/launch?token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA".into(),
                    )
                    .unwrap(),
                    selection: ["literal".into(), "literal".into(), "literal".into()],
                },
                limits,
                end,
                clock,
                chromium: Chromium::Running(surrogate),
                driver: Driver::Finished(driver),
                conversation,
                first_fault: None,
                capture,
                cursor: prefix,
                frame_start: prefix,
            }),
            _directory: directory,
        }
    }
    fn owner(&mut self) -> &mut BrowserController {
        self.owner.as_mut().unwrap()
    }
    fn finish(mut self) -> ControllerOutcome {
        self.owner().request_shutdown();
        let end = Instant::now() + Duration::from_secs(5);
        while !self.owner().poll_cleanup() {
            assert!(Instant::now() < end, "literal roots/readers not joined");
            std::thread::sleep(Duration::from_millis(1));
        }
        match self.owner.take().unwrap().into_finished() {
            ControllerFinish::Finished(outcome) => outcome,
            ControllerFinish::Pending(_) => panic!("literal cleanup remained pending"),
        }
    }
}
impl Drop for LiteralController {
    fn drop(&mut self) {
        if let Some(owner) = self.owner.as_mut() {
            owner.request_shutdown();
            let end = Instant::now() + Duration::from_secs(5);
            while !owner.poll_cleanup() && Instant::now() < end {
                std::thread::sleep(Duration::from_millis(1));
            }
        }
    }
}

#[test]
fn browser_controller_receive_01_exact_final_frame_then_actual_eof_joins() {
    let mut actual = LiteralController::prepare(COMPLETE);
    let interrupted = AtomicBool::new(false);
    let frame = actual.owner().poll(&interrupted);
    let terminal = actual.owner().poll(&interrupted);
    let outcome = actual.finish();
    assert_eq!(
        frame,
        Ok(ControllerProgress::Reply(
            ControllerReply::SourceDisconnected
        ))
    );
    assert_eq!(terminal, Ok(ControllerProgress::DriverJoined));
    assert!(outcome.first_fault().is_none());
    assert!(matches!(
        outcome.driver().unwrap().stdout_terminal(),
        ReadTerminal::Eof
    ));
}

#[test]
fn browser_controller_receive_02_unterminated_full_frame_refuses() {
    let mut bytes = COMPLETE.to_vec();
    *bytes.last_mut().unwrap() = b'!';
    let mut actual = LiteralController::prepare(&bytes);
    let terminal = actual.owner().poll(&AtomicBool::new(false));
    let outcome = actual.finish();
    assert_eq!(terminal, Err(ControllerFault::Output));
    assert_eq!(outcome.first_fault(), Some(&ControllerFault::Output));
}

#[test]
fn browser_controller_receive_03_actual_trailing_byte_refuses_join() {
    let mut bytes = COMPLETE.to_vec();
    bytes.push(b'!');
    let mut actual = LiteralController::prepare(&bytes);
    assert!(
        matches!(&actual.owner().driver, Driver::Finished(outcome) if outcome.first_fault().is_some())
    );
    let terminal = actual.owner().poll(&AtomicBool::new(false));
    let outcome = actual.finish();
    assert_eq!(terminal, Err(ControllerFault::Process));
    assert!(outcome.driver().unwrap().first_fault().is_some());
}

#[test]
fn browser_controller_observe_01_retained_actual_reply_survives_prior_cancel_and_end() {
    let mut actual = LiteralController::prepare_at(b"2 project-selected\n", 0, Conversation::SourceOpeningPending);
    let root_ids = actual.owner().ids();
    actual.owner().first_fault = Some(ControllerFault::Cancelled);
    actual.owner().end = Instant::now(); // Literal component original already elapsed.
    let reply = actual.owner().observe_source_retained();
    assert_eq!(actual.owner().ids(), root_ids);
    assert_eq!(actual.owner().first_fault, Some(ControllerFault::Cancelled));
    let outcome = actual.finish();
    assert_eq!(reply, Ok(ControllerProgress::Reply(ControllerReply::SourceOpening(ControllerChoiceReply::ProjectSelected))));
    assert_eq!(outcome.first_fault(), Some(&ControllerFault::Cancelled));
}

#[test]
fn browser_controller_observe_02_late_unknown_bytes_cannot_form_a_reply() {
    let mut actual = LiteralController::prepare_at(b"2 invented-result\n", 0, Conversation::SourceOpeningPending);
    actual.owner().first_fault = Some(ControllerFault::Cancelled);
    let reply = actual.owner().observe_source_retained();
    let outcome = actual.finish();
    assert_eq!(reply, Err(ControllerFault::Cancelled));
    assert_eq!(outcome.first_fault(), Some(&ControllerFault::Cancelled));
}
