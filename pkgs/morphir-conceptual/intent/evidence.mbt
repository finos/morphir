///|
pub(all) struct Claim {
  subject : ResolvedRef
  proposition : String
  author : Id
  scope : @ion.IonValue
  context : RevisionContext
}

///|
pub(all) struct Producer {
  id : Id
  version : Revision
  profile : Id
}

///|
pub(all) enum ReviewDecision {
  Accepted
  Rejected
}

///|
pub(all) enum AbsentReason {
  NotInvoked
  ExecutionError
  MissingResult
}

///|
pub(all) enum RunOutput {
  Observed(@ion.IonValue)
  Absent(AbsentReason)
}

///|
pub(all) enum ClauseObservation {
  Satisfied
  Violated
  NotApplicable
  InvalidArgument
  Unsupported
  Error
  InconclusiveObservation
}

///|
pub(all) struct ClauseResult {
  entity : Snapshot
  observation : ClauseObservation
}

///|
pub struct RunLimits {
  steps : Int32
  depth : Int32
}

///|
pub fn RunLimits::new(
  steps : Int32,
  depth : Int32,
) -> RunLimits raise InvalidInput {
  if steps <= 0 || depth <= 0 {
    raise InvalidInput("Run limits must be positive")
  }
  { steps, depth, }
}

///|
pub(all) struct RunObservation {
  value_profile : Id
  input : @ion.IonValue
  output : RunOutput
  clauses : Array[ClauseResult]
  evaluator : Producer
  target : String
  configuration : @ion.IonValue
  limits : RunLimits
  generated_case : @ion.IonValue?
  type_arguments : @ion.IonValue?
}

///|
pub(all) enum Observation {
  Run(RunObservation)
  Analysis(Producer, @ion.IonValue, @ion.IonValue)
  Review(Id, ReviewDecision, String)
}

///|
pub(all) struct Evidence {
  origin : String
  context : RevisionContext
  observation : Observation
}

///|
pub(all) enum Polarity {
  Supporting
  Contradicting
} derive(Eq, Debug)

///|
pub extend Polarity with Eq::{equal, not_equal}

///|
pub extend Polarity with @debug.Debug::{to_repr}

///|
pub(all) enum EvidenceAvailability {
  Unknown
  Present
  InvalidClaim
} derive(Eq, Debug)

///|
pub extend EvidenceAvailability with Eq::{equal, not_equal}

///|
pub extend EvidenceAvailability with @debug.Debug::{to_repr}

///|
pub(all) struct EvidenceAssessment {
  relationship_model : Snapshot
  relationship : Id
  reference : ResolvedRef
  polarity : Polarity
  evidence : Evidence
  freshness : Freshness
}

///|
pub(all) struct ClaimAssessment {
  claim : ResolvedRef
  claim_freshness : Freshness
  availability : EvidenceAvailability
  observations : Array[EvidenceAssessment]
  inspection : Inspection
}

///|
/// Currency is an exact revision comparison, never a proof. An observation's
/// payload and kind survive even when stale, inconclusive or contradicting.
pub fn assess_claim(
  model : Model,
  reference : ResolvedRef,
  requested : RevisionContext,
) -> ClaimAssessment {
  let inspection = inspect(model)
  let invalid : ClaimAssessment = {
    claim: reference,
    claim_freshness: Inconclusive,
    availability: InvalidClaim,
    observations: [],
    inspection,
  }
  if inspection.has_errors() {
    return invalid
  }
  let entity = match resolve(model, reference) {
    Ok(e) => e
    Err(_) => return invalid
  }
  guard entity.content is Claim(claim) else { return invalid }
  guard find_model(model, reference.model) is Some(claim_owner) else {
    return invalid
  }
  let required = required_context(model, claim_owner, claim, entity.source_refs)
  let observations : Array[EvidenceAssessment] = []
  for (link_owner, _) in model_closure(model).0 {
    for link in usable_relationships(link_owner) {
      if (link.predicate == Supports || link.predicate == Contradicts) &&
        link.target is Resolved(target) &&
        target == reference {
        if resolve(model, link.subject) is Ok(evidence_entity) &&
          evidence_entity.content is Evidence(evidence) {
          observations.push({
            relationship_model: link_owner.identity,
            relationship: link.id,
            reference: link.subject,
            polarity: if link.predicate == Supports {
              Supporting
            } else {
              Contradicting
            },
            evidence,
            freshness: compare_context(
              evidence.context,
              requested,
              observation_context(
                model, required, link_owner, link, evidence_entity, evidence,
              ),
            ),
          })
        }
      }
    }
  }
  {
    claim: reference,
    claim_freshness: compare_context(claim.context, requested, required),
    availability: if observations.is_empty() {
      Unknown
    } else {
      Present
    },
    observations,
    inspection,
  }
}
