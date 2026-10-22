//! Source-selected monotone action input. No physical execution or verdict.
use super::*;
use std::sync::{Mutex, MutexGuard};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserActionCursorFault {
    AlreadyOutstanding,
    OutstandingAbandoned,
    ForeignAction,
    Unsupported(BrowserUnsupportedActionKind),
    Poisoned,
}
#[derive(Debug)]
pub enum BrowserActionIssueError {
    Input(BrowserInputError),
    Cursor(BrowserActionCursorFault),
}
impl From<BrowserInputError> for BrowserActionIssueError {
    fn from(error: BrowserInputError) -> Self {
        Self::Input(error)
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BrowserActionCursorTerminal {
    NoneIssued,
    /// Logical source progression only, never a physical execution certificate.
    FullSourceActionsConsumed {
        actions: usize,
    },
    Incomplete {
        consumed: usize,
        pending: Option<usize>,
        remaining: usize,
    },
    Refused {
        position: usize,
        cause: BrowserActionCursorFault,
    },
}
enum Phase {
    Ready,
    Issued(usize),
    Exhausted,
    Refused {
        position: usize,
        cause: BrowserActionCursorFault,
    },
}
pub(super) struct BrowserActionCursor<'case> {
    inputs: inputs::BrowserActionInputs<'case>,
    total: usize,
    phase: Phase,
}
impl<'case> BrowserActionCursor<'case> {
    pub(super) fn prepare(
        inputs: inputs::BrowserActionInputs<'case>,
        loans: &mut inputs::BrowserOwnerLoans<'_>,
    ) -> Result<Self, BrowserInputError> {
        let total = inputs.len();
        let bytes = total
            .checked_mul(size_of::<BrowserExecutionAction<'_, '_, '_, '_, '_, '_, '_>>())
            .ok_or_else(|| overflow(loans))?;
        let initialized = total
            .checked_mul(size_of::<Self>())
            .and_then(|n| n.checked_add(bytes))
            .ok_or_else(|| overflow(loans))?;
        // The embedding run's actual layout already funds this cursor and Mutex.
        // Pay every possible issued wrapper and monotone state write before issue.
        reserve(loans, bytes, total, initialized)?;
        Ok(Self {
            inputs,
            total,
            phase: Phase::Ready,
        })
    }
    fn position(&self) -> usize {
        match self.phase {
            Phase::Issued(position) | Phase::Refused { position, .. } => position,
            _ => self.total - self.inputs.len(),
        }
    }
    fn refuse(
        &mut self,
        position: usize,
        cause: BrowserActionCursorFault,
    ) -> BrowserActionCursorFault {
        if let Phase::Refused { cause, .. } = self.phase {
            cause
        } else {
            self.phase = Phase::Refused { position, cause };
            cause
        }
    }
    fn terminal(&self) -> BrowserActionCursorTerminal {
        match self.phase {
            Phase::Ready if self.inputs.len() == self.total => {
                BrowserActionCursorTerminal::NoneIssued
            }
            Phase::Ready => BrowserActionCursorTerminal::Incomplete {
                consumed: self.total - self.inputs.len(),
                pending: None,
                remaining: self.inputs.len(),
            },
            Phase::Issued(position) => BrowserActionCursorTerminal::Incomplete {
                consumed: self.total - self.inputs.len() - 1,
                pending: Some(position),
                remaining: self.inputs.len() + 1,
            },
            Phase::Exhausted if self.total > 0 => {
                BrowserActionCursorTerminal::FullSourceActionsConsumed {
                    actions: self.total,
                }
            }
            Phase::Exhausted => BrowserActionCursorTerminal::NoneIssued,
            Phase::Refused { position, cause } => {
                BrowserActionCursorTerminal::Refused { position, cause }
            }
        }
    }
}
fn lock<'a, 'case>(
    mutex: &'a Mutex<BrowserActionCursor<'case>>,
) -> MutexGuard<'a, BrowserActionCursor<'case>> {
    match mutex.lock() {
        Ok(cursor) => cursor,
        Err(poison) => {
            let mut cursor = poison.into_inner();
            let position = cursor.position();
            cursor.refuse(position, BrowserActionCursorFault::Poisoned);
            cursor
        }
    }
}
enum TokenState {
    Outstanding,
    #[cfg(test)]
    Consumed,
}
/// A single source-issued input. Getters are DATA only; fixed operation factories
/// must validate this exact token, not reconstruct authority from its position.
pub struct BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied> {
    owner: &'a PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
    input: inputs::BrowserActionInput<'case>,
    state: TokenState,
}
impl<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub fn position(&self) -> usize {
        self.input.position()
    }
    pub fn kind(&self) -> BrowserActionKind<'case> {
        super::super::project_browser_action(self.input.kind())
    }
    /// Pure source-projection control. Production has no fake completion path;
    /// genuine fixed controller factories will own their actual settlement seam.
    #[cfg(test)]
    fn consume_source_only_for_test(
        mut self,
        run: &PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        run.validate_action(&self, loans)?;
        let mut cursor = lock(&run.actions);
        cursor.phase = if cursor.inputs.len() == 0 {
            Phase::Exhausted
        } else {
            Phase::Ready
        };
        self.state = TokenState::Consumed;
        Ok(())
    }
}
impl Drop for BrowserExecutionAction<'_, '_, '_, '_, '_, '_, '_> {
    fn drop(&mut self) {
        if matches!(self.state, TokenState::Outstanding) {
            lock(&self.owner.actions).refuse(
                self.input.position(),
                BrowserActionCursorFault::OutstandingAbandoned,
            );
        }
    }
}
impl<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
    PreparedBrowserClientRun<'compiled, 'run, 'case, 'sources, 'raw, 'supplied>
{
    pub fn next_action<'a>(
        &'a self,
        loans: &mut BrowserLoans<'_, '_>,
    ) -> Result<
        Option<BrowserExecutionAction<'a, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>>,
        BrowserActionIssueError,
    > {
        loans.ready_for_run(self.global, self.child)?;
        self.child
            .identity
            .while_active(|| {
                let mut cursor = lock(&self.actions);
                match cursor.phase {
                    Phase::Refused { cause, .. } => {
                        return Err(BrowserActionIssueError::Cursor(cause));
                    }
                    Phase::Issued(position) => {
                        return Err(BrowserActionIssueError::Cursor(
                            cursor.refuse(position, BrowserActionCursorFault::AlreadyOutstanding),
                        ));
                    }
                    Phase::Exhausted => return Ok(None),
                    Phase::Ready => {}
                }
                let Some(input) = cursor.inputs.next() else {
                    cursor.phase = Phase::Exhausted;
                    return Ok(None);
                };
                let position = input.position();
                if let inputs::BrowserActionKind::Unsupported { kind } = input.kind() {
                    return Err(BrowserActionIssueError::Cursor(
                        cursor.refuse(position, BrowserActionCursorFault::Unsupported(kind)),
                    ));
                }
                cursor.phase = Phase::Issued(position);
                Ok(Some(BrowserExecutionAction {
                    owner: self,
                    input,
                    state: TokenState::Outstanding,
                }))
            })
            .map_err(|cause| BrowserActionIssueError::Input(source(cause)))?
    }
    pub fn validate_action(
        &self,
        action: &BrowserExecutionAction<'_, 'compiled, 'run, 'case, 'sources, 'raw, 'supplied>,
        loans: &BrowserLoans<'_, '_>,
    ) -> Result<(), BrowserActionIssueError> {
        loans.ready_for_run(self.global, self.child)?;
        if !std::ptr::eq(action.owner, self) {
            return Err(BrowserActionIssueError::Input(source(
                BrowserSourceFault::ForeignSource,
            )));
        }
        let cursor = lock(&self.actions);
        match cursor.phase {
            Phase::Issued(position)
                if position == action.input.position()
                    && matches!(action.state, TokenState::Outstanding) =>
            {
                Ok(())
            }
            Phase::Refused { cause, .. } => Err(BrowserActionIssueError::Cursor(cause)),
            _ => Err(BrowserActionIssueError::Cursor(
                BrowserActionCursorFault::ForeignAction,
            )),
        }
    }
    pub fn actions_terminal(&self) -> BrowserActionCursorTerminal {
        lock(&self.actions).terminal()
    }
}
#[cfg(test)]
#[path = "actions/tests.rs"]
mod tests;
