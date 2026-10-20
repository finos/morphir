//! One caller-configured cumulative owner for static closure, not runtime pools.
use super::FixtureAlias;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Resource {
    Definitions,
    References,
    LookupBytes,
    StructuralVisits,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ClosureError {
    InvalidLimits,
    Resource(Resource),
    SizeOverflow,
    Allocation,
    Duplicate,
    Missing,
    ForwardReference,
    InvalidPrearmRole,
    ExpectedDataAsInput,
    Ambiguous,
    Semantic,
}
#[derive(Debug, Clone, Copy)]
pub(super) struct ClosureLimits {
    definitions: usize,
    references: usize,
    lookup_bytes: usize,
    structural_visits: usize,
}
impl ClosureLimits {
    pub(super) fn new(
        definitions: usize,
        references: usize,
        lookup_bytes: usize,
        structural_visits: usize,
    ) -> Result<Self, ClosureError> {
        if [definitions, references, lookup_bytes, structural_visits]
            .into_iter()
            .any(|value| value > isize::MAX as usize)
        {
            return Err(ClosureError::InvalidLimits);
        }
        Ok(Self {
            definitions,
            references,
            lookup_bytes,
            structural_visits,
        })
    }
}
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(super) struct ClosureUsage {
    pub(super) definitions: usize,
    pub(super) references: usize,
    pub(super) lookup_bytes: usize,
    pub(super) structural_visits: usize,
    /// Positive-capacity allocator attempts, including failed attempts.
    pub(super) allocation_attempts: usize,
}
/// No Clone/reset or conversion to any producer/client resource authority.
pub(super) struct ClosureOwner {
    limits: ClosureLimits,
    usage: ClosureUsage,
    fault: Option<ClosureError>,
}
impl ClosureOwner {
    pub(super) fn new(limits: ClosureLimits) -> Self {
        Self {
            limits,
            usage: ClosureUsage::default(),
            fault: None,
        }
    }
    pub(super) fn usage(&self) -> ClosureUsage {
        self.usage
    }
    pub(super) fn ready(&self) -> Result<(), ClosureError> {
        self.fault.map_or(Ok(()), Err)
    }
    pub(super) fn refuse<T>(&mut self, error: ClosureError) -> Result<T, ClosureError> {
        let first = *self.fault.get_or_insert(error);
        Err(first)
    }
    pub(super) fn charge(&mut self, resource: Resource, count: usize) -> Result<(), ClosureError> {
        self.ready()?;
        let (used, maximum) = match resource {
            Resource::Definitions => (&mut self.usage.definitions, self.limits.definitions),
            Resource::References => (&mut self.usage.references, self.limits.references),
            Resource::LookupBytes => (&mut self.usage.lookup_bytes, self.limits.lookup_bytes),
            Resource::StructuralVisits => (
                &mut self.usage.structural_visits,
                self.limits.structural_visits,
            ),
        };
        match used.checked_add(count).filter(|next| *next <= maximum) {
            Some(next) => {
                *used = next;
                Ok(())
            }
            None => self.refuse(ClosureError::Resource(resource)),
        }
    }
    pub(super) fn reserve<T>(&mut self, values: &mut Vec<T>) -> Result<(), ClosureError> {
        self.ready()?;
        let bytes = values
            .len()
            .checked_add(1)
            .and_then(|length| length.checked_mul(std::mem::size_of::<T>()))
            .filter(|bytes| *bytes <= isize::MAX as usize);
        if bytes.is_none() {
            return self.refuse(ClosureError::SizeOverflow);
        }
        if values.len() == values.capacity() {
            let Some(attempts) = self.usage.allocation_attempts.checked_add(1) else {
                return self.refuse(ClosureError::SizeOverflow);
            };
            self.usage.allocation_attempts = attempts;
            if values.try_reserve_exact(1).is_err() {
                return self.refuse(ClosureError::Allocation);
            }
        }
        Ok(())
    }
    pub(super) fn same_alias(
        &mut self,
        first: &FixtureAlias,
        second: &FixtureAlias,
    ) -> Result<bool, ClosureError> {
        self.same_text(first.as_str(), second.as_str())
    }
    pub(super) fn same_text(&mut self, first: &str, second: &str) -> Result<bool, ClosureError> {
        self.ready()?;
        let first = first.as_bytes();
        let second = second.as_bytes();
        if first.len() != second.len() {
            return Ok(false);
        }
        for index in 0..first.len() {
            self.charge(Resource::LookupBytes, 2)?;
            if first[index] != second[index] {
                return Ok(false);
            }
        }
        Ok(true)
    }
}
