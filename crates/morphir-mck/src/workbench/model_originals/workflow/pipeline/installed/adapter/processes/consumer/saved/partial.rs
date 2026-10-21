//! Incomplete recorded DATA. No source, worker, destination or scratch completion.
use super::*;
use crate::workbench::model_originals::workflow::{
    installed_client::InstalledClientPlan,
    observation_check::{CompareOwner, InstalledClientFault as Fault, ObservationError, installed},
};
literal! { pub Prefix => "prefix" }
record! { pub HostPrefix {
    association:model::InvocationAssociation=>"association",
    selection:model::SelectedRuntimeData=>"selection",
    events:Items<model::SequencedSocketEvent,0,{usize::MAX}> =>"events"
} }
record! { pub Context {
    kind:Prefix=>"kind",
    implementation:model::implementation::ImplementationObservation=>"implementation",
    host:HostPrefix=>"host"
} }
pub(in crate::workbench::model_originals::workflow) struct Partial {
    process: model::ProcessMeasurement,
    claim: Option<Document>,
    record: Record,
    context: Context,
    frames: Vec<model::ParsedFrame>,
    protocol: Result<model::ProtocolFacts, Fault>,
}
impl Partial {
    pub(in crate::workbench::model_originals::workflow) fn matches_first(
        &self,
        summary: crate::workbench::model_originals::workflow::pipeline::wire::FailureSummary,
        owner: &mut Decoder,
    ) -> Result<bool, DecodeError> {
        let Completion::Interrupted { first } = &self.record.completion else {
            return Ok(true);
        };
        let lengths = [
            first.phase.as_str().len(),
            summary.phase.len(),
            first.code.as_str().len(),
            summary.code.len(),
            first.message.as_str().len(),
            summary.message.len(),
        ];
        owner.bytes(
            lengths
                .into_iter()
                .try_fold(0usize, usize::checked_add)
                .ok_or(DecodeError::Limits)?,
        )?;
        Ok(first.phase.as_str() == summary.phase
            && first.code.as_str() == summary.code
            && first.message.as_str() == summary.message)
    }
    pub(in crate::workbench::model_originals::workflow) fn decode(
        doc: &Document,
        owner: &mut Decoder,
    ) -> Result<Self, DecodeError> {
        crate::workbench::model_originals::workflow::installed_client::copy_credit(doc, owner)?;
        let fields = Fields::new(doc, &["kind", "process", "operation", "context"], owner)?;
        fields.field::<Recorded>("kind", owner)?;
        let process: model::ProcessMeasurement = fields.field("process", owner)?;
        let claim = match process.stdout.utf8(owner)? {
            Some(text) => model::literal(text, owner)?,
            None => None,
        };
        let record = fields.field("operation", owner)?;
        let context: Context = fields.field("context", owner)?;
        owner.slots(context.host.events.0.len())?;
        let mut frames = Vec::new();
        frames
            .try_reserve_exact(context.host.events.0.len())
            .map_err(|_| DecodeError::Allocation)?;
        for (event, _) in context.host.events.0.iter().enumerate() {
            if let Some(raw) = model::prefix_payload(&context.host.events.0, event) {
                frames.push(model::ParsedFrame {
                    event,
                    document: model::literal(raw, owner)?,
                });
            }
        }
        let protocol = model::prepare_prefix_protocol(
            &context.host.selection,
            &context.host.events.0,
            &frames,
            owner,
        )?;
        Ok(Self {
            process,
            claim,
            record,
            context,
            frames,
            protocol,
        })
    }
    pub(in crate::workbench::model_originals::workflow) fn check(
        &self,
        plan: &InstalledClientPlan<'_>,
        owner: &mut CompareOwner,
    ) -> Result<(), ObservationError> {
        owner.ready()?;
        owner.visit()?;
        check::check(owner,
            usize::try_from(self.process.action_index.0).ok().and_then(|index|plan.actions().nth(index)).is_some_and(|action|matches!(action,crate::workbench::model_originals::workflow::installed_client::Action::Run{command:crate::workbench::model_originals::workflow::installed_client::Command::Publish,..})),
            Fault::ConsumerAssociation)?;
        let binding = check::association(
            &self.record,
            &self.process,
            &self.context.implementation,
            owner,
        )?;
        let helper_expectation =
            check::published_success(&self.process, self.claim.as_ref(), owner)?;
        installed::check_prefix_implementation(
            plan,
            &self.context.implementation,
            &self.process,
            owner,
        )?;
        let mut roles = [false; 2];
        let mut facts = [false; 3];
        for endpoint in &self.record.endpoints.0 {
            owner.visit()?;
            let index = usize::from(endpoint.role == Role::Helper);
            check::check(owner, !roles[index], Fault::ConsumerTranscript)?;
            roles[index] = true;
            let mut closed = false;
            let mut delivery_pending = false;
            let mut helper_started = false;
            let mut business = 0;
            for (position, row) in endpoint.frames.0.iter().enumerate() {
                owner.visit()?;
                let valid = !closed
                    && !delivery_pending
                    && row.frame.sequence() == position as u64
                    && owner.same_text(row.frame.version(), wire::VERSION)?;
                check::check(owner, valid, Fault::ConsumerTranscript)?;
                let total = ack_length(row.frame.sequence());
                match row.delivery {
                    Delivery::Written {
                        total: Natural(actual),
                    } => check::check(owner, actual == total, Fault::ConsumerTranscript)?,
                    Delivery::Prefix {
                        written: Natural(written),
                        total: Natural(actual),
                    } => {
                        check::check(
                            owner,
                            actual == total && written < total,
                            Fault::ConsumerTranscript,
                        )?;
                        delivery_pending = true;
                    }
                    Delivery::NotIssued {} => delivery_pending = true,
                }
                if position == 0 {
                    check::check(
                        owner,
                        matches!(row.frame, wire::Frame::Open { .. }),
                        Fault::ConsumerTranscript,
                    )?;
                    continue;
                }
                match &row.frame {
                    wire::Frame::Fact { fact, .. } => {
                        let slot = match fact {
                            wire::Fact::Release { .. } => 0,
                            wire::Fact::Commit { .. } => 1,
                            wire::Fact::Cleanup { .. } => 2,
                        };
                        check::check(
                            owner,
                            !facts[slot] && (slot == 0) == (endpoint.role == Role::Helper),
                            Fault::ConsumerTranscript,
                        )?;
                        facts[slot] = true;
                        business += 1;
                        if slot == 0 {
                            check::release(
                                fact,
                                &self.context.host.selection,
                                &self.context.host.events.0,
                                &self.frames,
                                &self.protocol,
                                owner,
                            )?;
                            installed::check_prefix_protocol(
                                plan,
                                &self.context.host.selection,
                                &self.context.host.events.0,
                                &self.protocol,
                                owner,
                            )?;
                        }
                    }
                    wire::Frame::Close {
                        attempted,
                        started,
                        retained,
                        helper,
                        ..
                    } => {
                        check::check(
                            owner,
                            attempted.0 == business
                                && started.0 == business
                                && retained.0 == business,
                            Fault::ConsumerTranscript,
                        )?;
                        check::close_helper(
                            binding.launch,
                            helper,
                            helper_started,
                            &endpoint.role,
                            helper_expectation,
                            owner,
                        )?;
                        closed = true;
                    }
                    wire::Frame::HelperStarted { launch, .. } => {
                        check::started_helper(
                            &binding,
                            launch,
                            helper_started,
                            &endpoint.role,
                            owner,
                        )?;
                        helper_started = true;
                    }
                    wire::Frame::Open { .. } => {
                        return check::check(owner, false, Fault::ConsumerTranscript);
                    }
                }
            }
            if matches!(self.record.completion, Completion::Drained {}) {
                check::check(
                    owner,
                    matches!(
                        endpoint.terminal,
                        Terminal::Drained {} | Terminal::Unused {}
                    ) && endpoint.fault.0.is_none()
                        && !delivery_pending,
                    Fault::ConsumerTranscript,
                )?;
            }
            match endpoint.terminal {
                Terminal::CloseRetained {} => {
                    check::check(owner, closed && delivery_pending, Fault::ConsumerTranscript)?
                }
                Terminal::CloseAckWritten {} | Terminal::Drained {} => check::check(
                    owner,
                    closed && !delivery_pending,
                    Fault::ConsumerTranscript,
                )?,
                Terminal::Unused {} => check::check(
                    owner,
                    endpoint.role == Role::Helper && endpoint.frames.0.is_empty(),
                    Fault::ConsumerTranscript,
                )?,
                _ => check::check(owner, !closed, Fault::ConsumerTranscript)?,
            }
        }
        installed::check_prefix_events(
            &self.context.host.selection,
            &self.context.host.events.0,
            &self.frames,
            owner,
        )
    }
}
impl Serialize for Partial {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        let mut map = serializer.serialize_map(Some(4))?;
        map.serialize_entry("kind", &Recorded)?;
        map.serialize_entry("process", &self.process)?;
        map.serialize_entry("operation", &self.record)?;
        map.serialize_entry("context", &self.context)?;
        map.end()
    }
}
fn ack_length(sequence: u64) -> u64 {
    4 + b"{\"kind\":\"retained\",\"version\":\"".len() as u64
        + wire::VERSION.len() as u64
        + b"\",\"sequence\":".len() as u64
        + u64::from(sequence.checked_ilog10().unwrap_or(0))
        + 2
}
