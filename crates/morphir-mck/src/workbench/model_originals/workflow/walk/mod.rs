//! Exhaustive typed alias traversal. No JSON, filesystem, or runtime lookup.
//! The static sites are issued only by the frozen descriptor macros below.
use super::{FixtureAlias, Items, Natural, Nullable, Presence, Text, UniqueItems, domain, input};

#[path = "site.rs"]
mod site;
pub(super) use site::{Operand, Site};

#[derive(Debug, Clone, Copy)]
pub(super) enum Segment {
    Root,
    Field(Site),
    Item(usize),
    Effect(SubjectKind),
    NativeBoundary(NativePending),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum SubjectKind {
    Maintained(crate::workbench::model_originals::EffectKind),
    ManifestFetch,
    WorkspaceOpen,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum NativePending {
    Initialize,
    Choose,
    Open,
}

/// Borrowed stack links preserve nested local scopes without heap allocation.
pub(super) struct Trail<'a> {
    pub(super) parent: Option<&'a Trail<'a>>,
    pub(super) segment: Segment,
}

pub(super) trait AliasSink<'source> {
    type Error;
    /// Required cumulative structural-work guard, called before each visit.
    /// This is a compiler caller limit, not a scenario metadata pool.
    fn enter(&mut self, trail: &Trail<'_>) -> Result<(), Self::Error>;
    fn alias(&mut self, alias: &'source FixtureAlias, trail: &Trail<'_>)
    -> Result<(), Self::Error>;
}

pub(super) trait WalkAliases {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error>;
}

impl WalkAliases for FixtureAlias {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        sink.alias(self, trail)
    }
}
impl<T: WalkAliases, const MIN: usize, const MAX: usize> WalkAliases for Items<T, MIN, MAX> {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        for (index, value) in self.0.iter().enumerate() {
            value.walk(
                &Trail {
                    parent: Some(trail),
                    segment: Segment::Item(index),
                },
                sink,
            )?;
        }
        Ok(())
    }
}
impl<T: WalkAliases, const MIN: usize, const MAX: usize> WalkAliases for UniqueItems<T, MIN, MAX> {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        for (index, value) in self.0.iter().enumerate() {
            value.walk(
                &Trail {
                    parent: Some(trail),
                    segment: Segment::Item(index),
                },
                sink,
            )?;
        }
        Ok(())
    }
}
impl<T: WalkAliases> WalkAliases for Nullable<T> {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        if let Some(value) = &self.0 {
            value.walk(trail, sink)?;
        }
        Ok(())
    }
}
impl<T: WalkAliases> WalkAliases for Presence<T> {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        if let Self::Present(value) = self {
            value.walk(trail, sink)?;
        }
        Ok(())
    }
}
impl<T: WalkAliases> WalkAliases for Box<T> {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)?;
        self.as_ref().walk(trail, sink)
    }
}

macro_rules! plain {
    ($($ty:ty),* $(,)?) => { $(impl WalkAliases for $ty {
        fn walk<'source, S: AliasSink<'source>>(&'source self, trail: &Trail<'_>, sink: &mut S) -> Result<(), S::Error> {
            sink.enter(trail)
        }
    })* };
}
plain!(
    super::ContentSha256,
    super::SourcePath,
    super::U64Token,
    super::RawJson,
    super::JsonBool,
    super::JsonNull
);
impl<const MIN: usize, const MAX: usize> WalkAliases for super::Text<MIN, MAX> {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)
    }
}
impl<const MIN: u64, const MAX: u64> WalkAliases for super::Natural<MIN, MAX> {
    fn walk<'source, S: AliasSink<'source>>(
        &'source self,
        trail: &Trail<'_>,
        sink: &mut S,
    ) -> Result<(), S::Error> {
        sink.enter(trail)
    }
}

// Only the shared recipe ADTs inherit the source operand from their genuine
// enclosing descriptor. Their byte grammar is shared; the diagnostic role is
// still the actual input/expected container, never a serialized label.
fn recipe_operand(mut trail: &Trail<'_>) -> Operand {
    loop {
        if let Segment::Field(site) = trail.segment {
            return site.parts().0;
        }
        match trail.parent {
            Some(parent) => trail = parent,
            None => return Operand::Input,
        }
    }
}
macro_rules! field {
    ($value:expr, $trail:ident, $sink:ident, Bytes, $variant:expr, $wire:literal) => { field!(@recipe $value,$trail,$sink,"Bytes",$variant,$wire) };
    ($value:expr, $trail:ident, $sink:ident, AtomicBytes, $variant:expr, $wire:literal) => { field!(@recipe $value,$trail,$sink,"AtomicBytes",$variant,$wire) };
    (@recipe $value:expr,$trail:ident,$sink:ident,$name:literal,$variant:expr,$wire:literal) => {{
        $value.walk(&Trail{parent:Some($trail),segment:Segment::Field(Site::descriptor(recipe_operand($trail),$name,$variant,$wire))},$sink)?;
    }};
    ($value:expr, $trail:ident, $sink:ident, $name:ident, $variant:expr, $wire:literal) => {{
        $value.walk(
            &Trail {
                parent: Some($trail),
                segment: Segment::Field(Site::descriptor(
                    OPERAND,
                    stringify!($name),
                    $variant,
                    $wire,
                )),
            },
            $sink,
        )?;
    }};
}
macro_rules! record {
    ($name:ident { $($field:ident : $ty:ty => $wire:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_wire:literal),* $(,)? })?) => {
        impl WalkAliases for $name {
            fn walk<'source, S: AliasSink<'source>>(&'source self, trail: &Trail<'_>, sink: &mut S) -> Result<(), S::Error> {
                sink.enter(trail)?;
                let context = context!(self, $name);
                let linked;
                let trail = if let Some(segment) = context {
                    linked = Trail { parent: Some(trail), segment };
                    &linked
                } else { trail };
                $(field!(&self.$field, trail, sink, $name, None, $wire);)*
                $($(field!(&self.$optional, trail, sink, $name, None, $optional_wire);)*)?
                Ok(())
            }
        }
    };
}
macro_rules! tagged {
    ($name:ident ($tag:literal) { $($variant:ident => $wire:literal { $($field:ident : $ty:ty => $key:literal),* $(,)? }),* $(,)? } $(delegates { $($delegate:ident => $delegate_wire:literal : $delegate_ty:ty),* $(,)? })?) => {
        impl WalkAliases for $name {
            fn walk<'source, S: AliasSink<'source>>(&'source self, trail: &Trail<'_>, sink: &mut S) -> Result<(), S::Error> {
                sink.enter(trail)?;
                let context = context!(self, $name);
                let linked;
                let trail = if let Some(segment) = context {
                    linked = Trail { parent: Some(trail), segment };
                    &linked
                } else { trail };
                match self {
                    $(Self::$variant { $($field),* } => { $(field!($field, trail, sink, $name, Some($wire), $key);)* },)*
                    $($(Self::$delegate(value) => field!(value, trail, sink, $name, Some($delegate_wire), "@delegate"),)*)?
                }
                Ok(())
            }
        }
    };
}
macro_rules! nested_tagged {
    ($name:ident ($tag:literal => $fixed:literal; $outer:literal, $nested:literal) { $($variant:ident => $wire:literal { $($field:ident : $ty:ty => $key:literal),* $(,)? }),* $(,)? }) => {
        tagged! { $name($tag) { $($variant => $wire { $($field: $ty => $key),* }),* } }
    };
}
macro_rules! kind {
    ($name:ident { $($variant:ident ($ty:ty)),* $(,)? }) => {
        impl WalkAliases for $name {
            fn walk<'source, S: AliasSink<'source>>(&'source self, trail: &Trail<'_>, sink: &mut S) -> Result<(), S::Error> {
                sink.enter(trail)?;
                match self { $(Self::$variant(value) => field!(value, trail, sink, $name, Some(stringify!($variant)), "@value"),)* }
                Ok(())
            }
        }
    };
}
macro_rules! words {
    (EffectKind { $($variant:ident => $wire:literal),* $(,)? }) => {
        plain!(EffectKind);
        impl From<&EffectKind> for super::SubjectKind {
            fn from(value: &EffectKind) -> Self { match value { $(EffectKind::$variant => planned_kind!($variant),)* } }
        }
    };
    ($name:ident { $($variant:ident => $wire:literal),* $(,)? }) => {
        plain!($name);
    };
}
macro_rules! planned_kind {
    (ManifestFetch) => {
        super::SubjectKind::ManifestFetch
    };
    (WorkspaceOpen) => {
        super::SubjectKind::WorkspaceOpen
    };
    ($variant:ident) => {
        super::SubjectKind::Maintained(crate::workbench::model_originals::EffectKind::$variant)
    };
}
macro_rules! context {
    ($value:expr, EffectRef) => {
        Some(Segment::Effect((&$value.kind).into()))
    };
    ($value:expr, ExpectedClientCheck) => {
        match $value {
            Self::PortCounts { effect_kind, .. } => Some(Segment::Effect(effect_kind.into())),
            _ => None,
        }
    };
    ($value:expr, ClientAction) => {
        match $value {
            Self::AwaitNativeBoundary { boundary, .. } => {
                Some(Segment::NativeBoundary(match boundary {
                    ClientActionAwaitNativeBoundaryBoundary::CatalogPending
                    | ClientActionAwaitNativeBoundaryBoundary::Initialized => {
                        NativePending::Initialize
                    }
                    ClientActionAwaitNativeBoundaryBoundary::WorkspaceSelected => {
                        NativePending::Choose
                    }
                    ClientActionAwaitNativeBoundaryBoundary::InspectionPending
                    | ClientActionAwaitNativeBoundaryBoundary::ModelOpenSettled => {
                        NativePending::Open
                    }
                }))
            }
            _ => None,
        }
    };
    ($value:expr, $name:ident) => {
        None::<Segment>
    };
}
macro_rules! text {
    ($name:ident { $($rest:tt)* }) => {
        plain!($name);
    };
}
macro_rules! literal {
    ($name:ident => $value:literal) => {
        plain!($name);
    };
}

mod input_walk {
    use super::*;
    use input::*;
    const OPERAND: Operand = Operand::Input;
    include!("input-descriptor.rs");
}
mod expected_walk {
    use super::*;
    use domain::*;
    const OPERAND: Operand = Operand::Expected;
    include!("expected-descriptor.rs");
}

mod native;

#[cfg(test)]
mod tests;

#[cfg(test)]
mod shared_byte_context_tests;
