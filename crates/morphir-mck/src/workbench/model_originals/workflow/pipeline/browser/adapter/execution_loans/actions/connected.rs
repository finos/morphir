//! Source-selected operands and the still-outstanding opening token. This
//! preparation performs no browser/FS effect and cannot settle the action.
use super::*;
use crate::workbench::model_originals::workflow::pipeline::browser::{
    BrowserDocumentProducer, BrowserHostTranscript, ControlledHostStimulus,
};
use std::time::Instant;
#[path = "connected/activity.rs"]
mod activity;
pub(in crate::workbench::model_originals::workflow::pipeline::browser) use activity::SourceControllerActivity;

#[derive(Clone, Copy)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct ConnectedChoiceFunding
{
    source_rows: usize,
    project_rows: usize,
    identity_bytes: usize,
}
impl ConnectedChoiceFunding {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn source_rows(
        &self,
    ) -> usize {
        self.source_rows
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn project_rows(
        &self,
    ) -> usize {
        self.project_rows
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn identity_bytes(
        &self,
    ) -> usize {
        self.identity_bytes
    }
}
enum ChoicePreparation {
    Unprepared,
    Prepared(ConnectedChoiceFunding),
}

/// One existing host transcript's original end plus the exact source0 child
/// relation. No caller Instant constructor or renewal is provided.
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceControllerLifetime {
    stamp: BrowserLoanStamp,
    end: Instant,
    binding: crate::workbench::model_originals::workflow::pipeline::browser::source_scope::BrowserSourceBinding,
    operation: SourceControllerOperationShape,
    association: crate::workbench::model_originals::workflow::pipeline::browser::collection::BrowserSourceHostAssociation,
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct SourceControllerOperationShape
{
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) opening_position: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) boundary_position: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) selection_bytes: usize,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) alias_bytes: usize,
}
impl SourceControllerLifetime {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn validate(
        &self,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserInputError> {
        loans.validate_relation_stamp(&self.stamp)?;
        self.while_business_active(|| ())
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn end(
        &self,
    ) -> Instant {
        self.end
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn operation_shape(
        &self,
    ) -> SourceControllerOperationShape {
        self.operation
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn while_active<R>(
        &self,
        action: impl FnOnce() -> R,
    ) -> Result<R, BrowserSourceFault> {
        // The binding already checks SAME parent→child once. Nesting the
        // retained stamp gate here would recursively acquire those locks.
        self.binding.while_active(action)
    }
    /// Source-specific business preparation and allocation use the original
    /// end inside the SAME source gate. This is separate from cleanup authority.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn while_business_active<
        R,
    >(
        &self,
        action: impl FnOnce() -> R,
    ) -> Result<R, BrowserInputError> {
        self.binding
            .while_active(|| self.association.while_current(action))
            .map_err(source)?
            .map_err(activity::activity_error)
    }
    /// Bookkeeping only: private actual owner finish must consume its covered
    /// processes/readers/files first. It remains usable after end/revocation.
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn retire_after_join_in_place(
        &mut self,
    ) -> Result<(), BrowserSourceFault> {
        self.binding.retire_after_join_in_place()
    }
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct ConnectedOpeningAction<
    'a,
    'compiled,
    'run,
    'case,
    'sources,
    'raw,
    'supplied,
> {
    action: BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    selection: [String; 3],
    pending: &'case str,
    choices: ConnectedChoiceFunding,
}
impl ConnectedOpeningAction<'_, '_, '_, '_, '_, '_, '_> {
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn position(
        &self,
    ) -> usize {
        self.action.position()
    }
}

pub(in crate::workbench::model_originals::workflow::pipeline::browser) struct PreparedConnectedOpening<
    'a,
    'compiled,
    'run,
    'case,
    'sources,
    'raw,
    'supplied,
> {
    action: BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) stamp: BrowserLoanStamp,
    selection: [String; 3],
    pending: &'case str,
    choices: ChoicePreparation,
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    PreparedConnectedOpening<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    // Operand-only allocation is a component fixture, not a production source
    // factory. Actual source preparation must bind its original host end first.
    #[cfg(test)]
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare(
        run: &'a PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        action: BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<Self, BrowserActionIssueError> {
        // Exact relation/prior faults precede operand tests, spending and copies.
        run.validate_action(&action, loans)?;
        if action.position() != 0 {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ));
        }
        let BrowserActionKind::BeginConnectedOpening {
            pending,
            project_id,
            source: selected,
            scope: BrowserScope::Complete,
            semantic: BrowserSemantic::Projection,
            inventory_max_entries: 256,
            read_max_bytes: 65536,
            ..
        } = action.kind()
        else {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ));
        };
        let operands = [selected.provider_id, selected.locator, project_id];
        let mut requested = size_of::<Self>();
        let mut visits = size_of::<Self>();
        for value in operands {
            requested = requested
                .checked_add(value.len())
                .ok_or_else(|| overflow(loans.inner))?;
            // One NUL scan, source-to-owned copy and command argument copy.
            visits = value
                .len()
                .checked_mul(3)
                .and_then(|n| visits.checked_add(n))
                .ok_or_else(|| overflow(loans.inner))?;
        }
        loans.reserve_controlled_host_storage(requested, operands.len() + 1, visits)?;
        // This fixed driver passes each operand as one argv value. The funded
        // scan rejects embedded NUL before any acquisition or string copy.
        if operands.iter().any(|value| value.as_bytes().contains(&0)) {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ));
        }
        let stamp = loans.prepare_relation_stamp()?;
        let mut selection = run
            .child
            .identity
            .while_active(|| {
                let mut selection = [String::new(), String::new(), String::new()];
                for (destination, source) in selection.iter_mut().zip(operands) {
                    destination
                        .try_reserve_exact(source.len())
                        .map_err(|_| InstalledObservationFault::Allocation)?;
                }
                Ok::<_, InstalledObservationFault>(selection)
            })
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?
            .map_err(|cause| loans.fail_collection(cause))?;
        for (destination, source) in selection.iter().zip(operands) {
            let spare = destination
                .capacity()
                .checked_sub(source.len())
                .ok_or_else(|| loans.fail_collection(InstalledObservationFault::LayoutMismatch))?;
            loans.reserve_controlled_host_storage(spare, 0, 0)?;
        }
        // No loan/source re-entry while the exact child gate is held.
        run.child
            .identity
            .while_active(|| {
                for (destination, source) in selection.iter_mut().zip(operands) {
                    destination.push_str(source);
                }
            })
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?;
        Ok(Self {
            action,
            stamp,
            selection,
            pending,
            choices: ChoicePreparation::Unprepared,
        })
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn provider_id(
        &self,
    ) -> &str {
        &self.selection[0]
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn locator(
        &self,
    ) -> &str {
        &self.selection[1]
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn project_id(
        &self,
    ) -> &str {
        &self.selection[2]
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn pending_alias(
        &self,
    ) -> &str {
        self.pending
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn position(
        &self,
    ) -> usize {
        self.action.position()
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn prepare_choice_funding(
        &mut self,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<&ConnectedChoiceFunding, BrowserActionIssueError> {
        self.action.owner.validate_action(&self.action, loans)?;
        loans.validate_controlled_source(stimulus)?;
        if stimulus.opening_action() != self.position() {
            return Err(BrowserActionIssueError::Input(source(
                BrowserSourceFault::ForeignSource,
            )));
        }
        if matches!(self.choices, ChoicePreparation::Unprepared) {
            let metadata = size_of::<ConnectedChoiceFunding>();
            loans.reserve_controlled_host_storage(metadata, 1, metadata)?;
            let (source_rows, source_bytes) =
                self.read_choice_document(stimulus.manifest_body(), loans, |doc, decode| {
                    choice_rows(
                        choice_field(doc, "initialSources", decode)?,
                        &["providerId", "locator"],
                        decode,
                    )
                })?;
            let requests = stimulus.requests().ok_or(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ))?;
            if requests.len() != stimulus.frames().len() {
                return Err(BrowserActionIssueError::Cursor(
                    BrowserActionCursorFault::UnsupportedOperation,
                ));
            }
            let metadata_work = requests
                .len()
                .checked_mul(size_of::<String>())
                .ok_or_else(|| overflow(loans.inner))?;
            loans.reserve_controlled_host_storage(0, 0, metadata_work)?;
            let mut projects = None;
            for (request, reply) in requests.iter().zip(stimulus.frames()) {
                let request_id = self.read_choice_document(request, loans, |doc, decode| {
                    let method = choice_text(choice_field(doc, "method", decode)?, decode)?;
                    decode.bytes("morphir.workspace.open".len())?;
                    if method != "morphir.workspace.open" {
                        return Ok(None);
                    }
                    choice_id(choice_field(doc, "id", decode)?).map(Some)
                })?;
                if let Some(request_id) = request_id {
                    projects = Some(self.read_choice_document(reply, loans, |doc, decode| {
                        if choice_id(choice_field(doc, "id", decode)?)? != request_id {
                            return Err(choice_shape());
                        }
                        let result = choice_field(doc, "result", decode)?;
                        let snapshot = choice_field(result, "snapshot", decode)?;
                        choice_rows(choice_field(snapshot, "projects", decode)?, &["id"], decode)
                    })?);
                    break;
                }
            }
            let (project_rows, project_bytes) = projects.ok_or(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ))?;
            let identity_bytes = source_bytes
                .checked_add(project_bytes)
                .ok_or_else(|| overflow(loans.inner))?;
            self.choices = ChoicePreparation::Prepared(ConnectedChoiceFunding {
                source_rows,
                project_rows,
                identity_bytes,
            });
        }
        let ChoicePreparation::Prepared(plan) = &self.choices else {
            unreachable!("prepared above")
        };
        Ok(plan)
    }

    fn read_choice_document<R>(
        &self,
        raw: &str,
        loans: &mut BrowserLoans<'_, '_>,
        project: impl FnOnce(
            &crate::json::strict::Document,
            &mut crate::workbench::model_originals::workflow::Decoder,
        ) -> Result<
            R,
            crate::workbench::model_originals::workflow::decode::DecodeError,
        >,
    ) -> Result<R, BrowserActionIssueError> {
        use crate::{
            json::strict, workbench::model_originals::workflow::observation_check::CompareResource,
        };
        let requested = strict::requested_document_storage_bound(raw.len())
            .and_then(|n| {
                strict::requested_diagnostic_storage_bound(raw.len()).and_then(|d| n.checked_add(d))
            })
            .ok_or_else(|| overflow(loans.inner))?;
        // Fixed schema paths inspect at most nine container/member names per
        // literal; 64 visits/128 comparison bytes per source byte overbound
        // all key scans and the single method test, including empty roots.
        let visits = raw
            .len()
            .checked_add(1)
            .and_then(|n| n.checked_mul(64))
            .ok_or_else(|| overflow(loans.inner))?;
        let comparisons = raw
            .len()
            .checked_add(1)
            .and_then(|n| n.checked_mul(128))
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(requested, raw.len(), visits)?;
        let (decode, _, comparison) = loans
            .inner
            .physical_owners()
            .map_err(BrowserInputError::from)?;
        comparison
            .charge(CompareResource::StructuralVisits, visits)
            .map_err(inputs::BrowserInputFault::Comparison)
            .map_err(BrowserInputError::from)?;
        comparison
            .charge(CompareResource::ComparisonBytes, comparisons)
            .map_err(inputs::BrowserInputFault::Comparison)
            .map_err(BrowserInputError::from)?;
        self.stamp
            .while_active(|| {
                let (doc, _) = decode.literal_with_raw(raw)?;
                project(&doc, decode)
            })
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?
            .map_err(inputs::BrowserInputFault::Decode)
            .map_err(BrowserInputError::from)
            .map_err(BrowserActionIssueError::from)
    }
    pub(in crate::workbench::model_originals::workflow::pipeline::browser) fn into_controller_parts(
        mut self,
        producer: &BrowserDocumentProducer,
        transcript: &BrowserHostTranscript,
        stimulus: &ControlledHostStimulus,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<
        (
            ConnectedOpeningAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
            SourceControllerLifetime,
        ),
        BrowserActionIssueError,
    > {
        self.action.owner.validate_action(&self.action, loans)?;
        let association = transcript
            .source_controller_association(producer, stimulus, self.position(), loans)
            .map_err(super::borrowed::association_error)?;
        let end = association.end();
        let choices = *self.prepare_choice_funding(stimulus, loans)?;
        // Inspect the genuine next source operand without issuing it early.
        // This first fixed path supports begin→inspection-boundary only; the
        // checkpoint at position2 and all other actions remain outstanding.
        let mut future = self
            .action
            .owner
            .input
            .actions(loans.inner)
            .map_err(BrowserInputError::from)?;
        let next = future.nth(1).ok_or(BrowserActionIssueError::Cursor(
            BrowserActionCursorFault::UnsupportedOperation,
        ))?;
        let BrowserActionKind::AwaitConnectedBoundary {pending: boundary_pending, boundary: BrowserConnectedBoundary::InspectionPending} =
            crate::workbench::model_originals::workflow::pipeline::browser::adapter::project_browser_action(next.kind()) else {
            return Err(BrowserActionIssueError::Cursor(BrowserActionCursorFault::UnsupportedOperation));
        };
        let alias_bytes = self
            .pending
            .len()
            .checked_add(boundary_pending.len())
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(0, 0, alias_bytes)?;
        let (_, _, compare) = loans
            .inner
            .physical_owners()
            .map_err(BrowserInputError::from)?;
        compare.charge(crate::workbench::model_originals::workflow::observation_check::CompareResource::ComparisonBytes, alias_bytes)
            .map_err(inputs::BrowserInputFault::Comparison).map_err(BrowserInputError::from)?;
        if !self
            .stamp
            .while_active(|| self.pending == boundary_pending)
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?
        {
            return Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::UnsupportedOperation,
            ));
        }
        let selection_bytes = self
            .selection
            .iter()
            .try_fold(0usize, |n, value| n.checked_add(value.len()))
            .ok_or_else(|| overflow(loans.inner))?;
        let operation = SourceControllerOperationShape {
            opening_position: self.position(),
            boundary_position: next.position(),
            selection_bytes,
            alias_bytes,
        };
        let metadata = size_of::<SourceControllerLifetime>()
            .checked_add(size_of::<ConnectedOpeningAction<'_, '_, '_, '_, '_, '_, '_>>())
            .ok_or_else(|| overflow(loans.inner))?;
        loans.reserve_controlled_host_storage(metadata, 2, metadata)?;
        // Genuine child debt precedes the first possible acquisition effect.
        // Drop alone remains Abandoned; logical action replies cannot retire it.
        let binding = self
            .action
            .owner
            .child
            .scope
            .bind(loans.inner)
            .map_err(issue)?;
        let Self {
            action,
            stamp,
            selection,
            pending,
            ..
        } = self;
        Ok((
            ConnectedOpeningAction {
                action,
                selection,
                pending,
                choices,
            },
            SourceControllerLifetime {
                stamp,
                end,
                binding,
                operation,
                association,
            },
        ))
    }
}

fn choice_shape() -> crate::workbench::model_originals::workflow::decode::DecodeError {
    crate::workbench::model_originals::workflow::decode::DecodeError::Shape(
        "prepared discovery/project choice input",
    )
}
fn choice_field<'d>(
    doc: &'d crate::json::strict::Document,
    name: &str,
    decode: &mut crate::workbench::model_originals::workflow::Decoder,
) -> Result<
    &'d crate::json::strict::Document,
    crate::workbench::model_originals::workflow::decode::DecodeError,
> {
    let crate::json::strict::Document::Object(fields) = doc else {
        return Err(choice_shape());
    };
    for (key, value) in fields {
        decode.bytes(key.len().saturating_add(name.len()))?;
        if key == name {
            return Ok(value);
        }
    }
    Err(choice_shape())
}
fn choice_text<'d>(
    doc: &'d crate::json::strict::Document,
    decode: &mut crate::workbench::model_originals::workflow::Decoder,
) -> Result<&'d str, crate::workbench::model_originals::workflow::decode::DecodeError> {
    let crate::json::strict::Document::String(text) = doc else {
        return Err(choice_shape());
    };
    decode.bytes(text.len())?;
    Ok(text)
}
fn choice_id(
    doc: &crate::json::strict::Document,
) -> Result<u64, crate::workbench::model_originals::workflow::decode::DecodeError> {
    let crate::json::strict::Document::Number(id) = doc else {
        return Err(choice_shape());
    };
    id.as_u64().filter(|id| *id > 0).ok_or_else(choice_shape)
}
fn choice_rows(
    doc: &crate::json::strict::Document,
    identities: &[&str],
    decode: &mut crate::workbench::model_originals::workflow::Decoder,
) -> Result<(usize, usize), crate::workbench::model_originals::workflow::decode::DecodeError> {
    let crate::json::strict::Document::Array(rows) = doc else {
        return Err(choice_shape());
    };
    let mut bytes = 0usize;
    for row in rows {
        for name in identities {
            let text = choice_text(choice_field(row, name, decode)?, decode)?;
            // These are disjoint decoded token spans of one bounded literal.
            bytes = bytes.checked_add(text.len()).ok_or_else(choice_shape)?;
        }
    }
    Ok((rows.len(), bytes))
}
