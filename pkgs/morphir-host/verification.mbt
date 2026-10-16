///|
pub(all) struct VerificationResult {
  reports : Array[@execution.Report]
  committed : Bool
  publication_error : String?
}

///|
/// A committed destination can still require publication cleanup/recovery.
pub fn VerificationResult::successful(self : VerificationResult) -> Bool {
  self.committed &&
  self.publication_error is None &&
  self.reports.all(r => r.successful())
}

///|
/// Verify every required target and dispose all leases before acquiring a lock.
/// Plain execute/verify remains publication-free; this is an explicit host action.
pub fn verify_and_publish(
  plans : Array[@execution.Plan],
  provider : @execution.Provider,
  evaluator : @execution.Evaluator,
  publisher : ContentPublisher,
  destination : String,
  cancelled~ : () -> Bool = fn() { false },
  observer~ : @observe.Observer = @observe.Observer::noop(),
) -> VerificationResult raise {
  if plans.is_empty() ||
    @workspace.normalize(destination) != destination ||
    destination == "." ||
    !publisher.write_bytes ||
    publisher.guarantee is HostManaged {
    raise @config.Invalid("verification.invalid_publication")
  }
  let first = plans[0]
  let snapshot = invocation_snapshot(first.library.artifacts)
  let suite = first.suite.encode("ion-binary")
  let targets = []
  for plan in plans {
    if targets.contains(plan.target) ||
      !provider.targets.contains(plan.target) ||
      invocation_snapshot(plan.library.artifacts) != snapshot ||
      plan.suite.encode("ion-binary") != suite {
      raise @config.Invalid("verification.matrix_identity")
    }
    targets.push(plan.target)
  }
  let reports = plans.map(plan => {
    @execution.run_report(
      plan,
      provider,
      evaluator=Some(evaluator),
      observer~,
      cancelled~,
    )
  })
  if !@execution.matrix_successful(targets, reports) || cancelled() {
    return {
      reports,
      committed: false,
      publication_error: Some("verification.failed"),
    }
  }
  if plans.any(plan => {
      invocation_snapshot(plan.library.artifacts) != snapshot ||
      plan.suite.encode("ion-binary") != suite
    }) {
    raise @config.Invalid("verification.source_changed")
  }
  let receipt = @protocol.record([
    ("profile", @ion.IonValue::string("morphir-verification-v1")),
    (
      "source_identity",
      @ion.IonValue::string(@identity.sha256(@utf8.encode(snapshot))),
    ),
    ("suite_identity", @ion.IonValue::string(@identity.sha256(suite))),
    (
      "required_targets",
      @ion.IonValue::list(targets.map(@ion.IonValue::string)),
    ),
    ("reports", @ion.IonValue::list(reports.map(r => r.to_ion()))),
  ])
  let artifacts = first.library.artifacts.map(a => @engine.ContentArtifact::{
    path: @workspace.join(destination, a.path),
    source: first.unit.id,
    content: match a.content {
      Text(s) => @data.Text(s)
      Binary(b) => @data.Binary(b)
    },
    format: "source",
  })
  let receipt_path = @workspace.join(destination, "verification.ionb")
  if artifacts.any(a => a.path == receipt_path) {
    raise @config.Invalid("verification.receipt_collision")
  }
  artifacts.push({
    path: receipt_path,
    source: first.unit.id,
    content: @data.Binary(@ion_binary.write_binary([receipt])),
    format: "ion-binary",
  })
  let mut transaction : ContentPublication? = None
  let mut committed = false
  let mut publication_error = None
  try {
    if cancelled() {
      raise @config.Invalid("Cancelled")
    }
    let publication = (publisher.begin)([destination])
    transaction = Some(publication)
    for artifact in artifacts {
      (publication.stage)(artifact)
    }
    if cancelled() {
      raise @config.Invalid("Cancelled")
    }
    (publication.commit)(destination)
    committed = true
  } catch {
    error => publication_error = Some(error_message(error))
  }
  if transaction is Some(publication) {
    (publication.abort)() catch {
      error =>
        publication_error = Some(
          publication_error.unwrap_or("") +
          " verification.cleanup_failed: " +
          error_message(error),
        )
    }
  }
  { reports, committed, publication_error, }
}
