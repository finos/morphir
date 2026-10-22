//! this borrowed view cannot restore a refused token or attest cleanup/joins.
use super::*;
pub struct BrowserConnectedPreparationFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    action: BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
}
impl BrowserConnectedPreparationFailure<'_, '_, '_, '_, '_, '_, '_> {
    /// Inspect the actual retained error as DATA without copying its payload.
    /// The returned value cannot borrow the held cursor guard.
    pub fn inspect_cause<R>(&self, inspect: impl FnOnce(&BrowserActionIssueError) -> R) -> R {
        let cursor = lock(&self.action.owner.actions);
        inspect(
            cursor
                .first_issue
                .as_ref()
                .expect("refused preparation retained its cause"),
        )
    }
}
impl std::fmt::Debug for BrowserConnectedPreparationFailure<'_, '_, '_, '_, '_, '_, '_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.inspect_cause(|cause| {
            f.debug_struct("BrowserConnectedPreparationFailure")
                .field("cause", cause)
                .finish()
        })
    }
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub(super) fn preparation_failed(
        mut self,
        cause: BrowserActionIssueError,
    ) -> BrowserConnectedPreparationFailure<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    {
        {
            let mut cursor = lock(&self.owner.actions);
            // The actual first error is MOVED once, without a new Arc or clone.
            cursor.first_issue.get_or_insert(cause);
            cursor.refuse(
                self.position(),
                BrowserActionCursorFault::PreparationRefused,
            );
        }
        self.state = TokenState::Refused;
        BrowserConnectedPreparationFailure { action: self }
    }
}
