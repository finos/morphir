//! Exhaustive typed alias traversal. No JSON, filesystem, or runtime lookup.
//! The static sites are issued only by the frozen descriptor macros below.
use super::{FixtureAlias, Items, Natural, Nullable, Presence, Text, UniqueItems, domain, input};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Operand {
    Input,
    Expected,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct Site {
    pub(super) operand: Operand,
    pub(super) declaration: &'static str,
    pub(super) variant: Option<&'static str>,
    pub(super) field: &'static str,
}

#[derive(Debug, Clone, Copy)]
pub(super) enum Segment {
    Root,
    Field(Site),
    Item(usize),
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

macro_rules! field {
    ($value:expr, $trail:ident, $sink:ident, $name:ident, $variant:expr, $wire:literal) => {{
        $value.walk(
            &Trail {
                parent: Some($trail),
                segment: Segment::Field(Site {
                    operand: OPERAND,
                    declaration: stringify!($name),
                    variant: $variant,
                    field: $wire,
                }),
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
    ($name:ident { $($variant:ident => $wire:literal),* $(,)? }) => {
        plain!($name);
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

#[cfg(test)]
mod tests;
