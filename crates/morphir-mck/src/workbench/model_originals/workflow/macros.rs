//! Declarations describe closed records and tagged alternatives. They do not
//! register a workflow operation or establish that an implementation ran it.
macro_rules! record {
    ($name:ident { $($field:ident : $ty:ty => $wire:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_wire:literal),* $(,)? })?) => {
        #[derive(Debug)]
        pub(super) struct $name { $(pub(super) $field: $ty,)* $($(pub(super) $optional: Presence<$optional_ty>,)*)? }
        impl Decode for $name {
            fn decode(value: &crate::json::strict::Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
                let fields = Fields::with_optional(value, &[$($wire),*], &[$($($optional_wire),*)?], owner)?;
                Ok(Self { $($field: fields.field::<$ty>($wire, owner)?,)* $($($optional: fields.presence::<$optional_ty>($optional_wire, owner)?,)*)? })
            }
        }
    };
}
macro_rules! kind {
    ($name:ident { $($variant:ident ($ty:ty)),* $(,)? }) => {
        #[derive(Debug)]
        pub(super) enum $name { $($variant($ty)),* }
        impl Decode for $name {
            fn decode(value: &crate::json::strict::Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
                owner.ready()?;
                match value {
                    $(crate::json::strict::Document::$variant(..) => <$ty>::decode(value, owner).map(Self::$variant),)*
                    _ => Err(DecodeError::Shape("closed JSON kind alternatives")),
                }
            }
        }
    };
}
macro_rules! words {
    ($name:ident { $($variant:ident => $wire:literal),* $(,)? }) => {
        #[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
        pub(super) enum $name { $($variant),* }
        impl Decode for $name {
            fn decode(value: &crate::json::strict::Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
                match string(value, owner)? {
                    $($wire => Ok(Self::$variant),)*
                    _ => Err(DecodeError::Shape("closed text alternatives")),
                }
            }
        }
        impl UniqueKey for $name {
            fn key(&self) -> &str { match self { $(Self::$variant => $wire),* } }
        }
    };
}
macro_rules! text {
    ($name:ident { min: $min:expr, max: unbounded, pattern: $pattern:literal }) => {
        text! { $name { min: $min, max: usize::MAX, pattern: $pattern } }
    };
    ($name:ident { min: $min:expr, max: $max:expr, pattern: $pattern:literal }) => {
        #[derive(Debug)]
        pub(super) struct $name(String);
        impl $name {
            pub(super) fn as_str(&self) -> &str {
                &self.0
            }
        }
        impl Decode for $name {
            fn decode(
                value: &crate::json::strict::Document,
                owner: &mut Decoder,
            ) -> Result<Self, DecodeError> {
                let text = string(value, owner)?;
                if !($min..=$max).contains(&text.chars().count()) {
                    return Err(DecodeError::Shape("pattern text length"));
                }
                static PATTERN: std::sync::OnceLock<Result<regex::Regex, regex::Error>> =
                    std::sync::OnceLock::new();
                let pattern = PATTERN
                    .get_or_init(|| regex::Regex::new($pattern))
                    .as_ref()
                    .map_err(|error| DecodeError::Value(error.to_string()))?;
                if !pattern.is_match(text) {
                    return Err(DecodeError::Shape("text pattern"));
                }
                Ok(Self(text.to_owned()))
            }
        }
    };
}
macro_rules! literal {
    ($name:ident => $literal:literal) => {
        #[derive(Debug)]
        pub(super) struct $name;
        impl Decode for $name {
            fn decode(
                value: &crate::json::strict::Document,
                owner: &mut Decoder,
            ) -> Result<Self, DecodeError> {
                Literal::decode_literal(value, $literal, owner)?;
                Ok(Self)
            }
        }
    };
}
macro_rules! tagged {
    ($name:ident ($tag:literal) { $($variant:ident => $wire:literal { $($field:ident : $ty:ty => $key:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_key:literal),* $(,)? })?),* $(,)? } $(delegates { $($delegate:ident => $delegate_wire:literal : $delegate_ty:ty),* $(,)? })?) => {
        #[derive(Debug)]
        pub(super) enum $name { $($variant { $($field: $ty,)* $($( $optional: Presence<$optional_ty>, )*)? },)* $($($delegate($delegate_ty),)*)? }
        impl Decode for $name {
            fn decode(value: &crate::json::strict::Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
                match discriminator(value, $tag, owner)? {
                    $($wire => {
                        let fields = Fields::with_optional(value, &[$tag, $($key),*], &[$($($optional_key),*)?], owner)?;
                        // Empty alternatives still perform the closed-object check.
                        let _ = &fields;
                        Ok(Self::$variant { $($field: fields.field::<$ty>($key, owner)?,)* $($($optional: fields.presence::<$optional_ty>($optional_key, owner)?,)*)? })
                    },)*
                    $($($delegate_wire => <$delegate_ty>::decode(value, owner).map(Self::$delegate),)*)?
                    _ => Err(DecodeError::Shape("closed tagged alternatives")),
                }
            }
        }
    };
}
macro_rules! nested_tagged {
    ($name:ident ($outer:literal => $outer_value:literal; $parent:literal, $tag:literal) { $($variant:ident => $wire:literal { $($field:ident : $ty:ty => $key:literal),* $(,)? }),* $(,)? }) => {
        #[derive(Debug)]
        pub(super) enum $name { $($variant { $($field: $ty),* }),* }
        impl Decode for $name {
            fn decode(value: &crate::json::strict::Document, owner: &mut Decoder) -> Result<Self, DecodeError> {
                if discriminator(value, $outer, owner)? != $outer_value { return Err(DecodeError::Shape("fixed outer discriminator")); }
                match nested_discriminator(value, $parent, $tag, owner)? {
                    $($wire => {
                        let fields = Fields::new(value, &[$outer, $($key),*], owner)?;
                        Ok(Self::$variant { $($field: fields.field::<$ty>($key, owner)?),* })
                    },)*
                    _ => Err(DecodeError::Shape("closed nested alternatives")),
                }
            }
        }
    };
}
