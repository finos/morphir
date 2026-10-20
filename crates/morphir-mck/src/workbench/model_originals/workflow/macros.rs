//! Declarations describe closed records and tagged alternatives. They do not
//! register a workflow operation or establish that an implementation ran it.
macro_rules! record {
    (pub $name:ident { $($field:ident : $ty:ty => $wire:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_wire:literal),* $(,)? })?) => {
        record! { @visible(pub) $name { $($field:$ty=>$wire),* } $(optional {$($optional:$optional_ty=>$optional_wire),*})? }
        impl serde::Serialize for $name {
            fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error> {
                use serde::ser::SerializeMap as _;
                let mut map=s.serialize_map(None)?;
                $(map.serialize_entry($wire,&self.$field)?;)*
                $($(if let Presence::Present(value)=&self.$optional {map.serialize_entry($optional_wire,value)?;})*)?
                map.end()
            }
        }
    };
    ($name:ident { $($field:ident : $ty:ty => $wire:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_wire:literal),* $(,)? })?) => {
        record! { @visible(pub(super)) $name { $($field:$ty=>$wire),* } $(optional {$($optional:$optional_ty=>$optional_wire),*})? }
    };
    (@visible($vis:vis) $name:ident { $($field:ident : $ty:ty => $wire:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_wire:literal),* $(,)? })?) => {
        #[derive(Debug)]
        $vis struct $name { $($vis $field: $ty,)* $($($vis $optional: Presence<$optional_ty>,)*)? }
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
    (pub $name:ident { $($variant:ident => $wire:literal),* $(,)? }) => {
        words! { @visible(pub) $name {$($variant=>$wire),*} }
        impl serde::Serialize for $name {
            fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error> {s.serialize_str(self.key())}
        }
    };
    ($name:ident { $($variant:ident => $wire:literal),* $(,)? }) => {
        words! { @visible(pub(super)) $name {$($variant=>$wire),*} }
    };
    (@visible($vis:vis) $name:ident { $($variant:ident => $wire:literal),* $(,)? }) => {
        #[derive(Debug, PartialEq, Eq, PartialOrd, Ord)]
        $vis enum $name { $($variant),* }
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
    (pub $name:ident { min: $min:expr, max: $max:expr, pattern: $pattern:literal }) => {
        text! { @visible(pub) $name {min:$min,max:$max,pattern:$pattern} }
        impl $name {
            pub fn new(text:&str)->Result<Self,super::DataValueError> {
                Self::validate_text(text)?;
                Ok(Self(text.to_owned()))
            }
            fn validate_text(text:&str)->Result<(),super::DataValueError> {
                if !($min..=$max).contains(&text.chars().count()) {return Err(super::DataValueError::Length)}
                let pattern=regex::Regex::new($pattern).map_err(|_|super::DataValueError::Pattern)?;
                if !pattern.is_match(text) {return Err(super::DataValueError::Pattern)}
                Ok(())
            }
        }
        impl serde::Serialize for $name {
            fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error> {s.serialize_str(self.as_str())}
        }
    };
    ($name:ident { min: $min:expr, max: unbounded, pattern: $pattern:literal }) => {
        text! { $name { min: $min, max: usize::MAX, pattern: $pattern } }
    };
    ($name:ident { min: $min:expr, max: $max:expr, pattern: $pattern:literal }) => {
        text! { @visible(pub(super)) $name {min:$min,max:$max,pattern:$pattern} }
    };
    (@visible($vis:vis) $name:ident { min: $min:expr, max: $max:expr, pattern: $pattern:literal }) => {
        #[derive(Debug)]
        $vis struct $name(String);
        impl $name {
            $vis fn as_str(&self) -> &str {
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
    (pub $name:ident => $literal:literal) => {
        literal! {@visible(pub) $name=>$literal}
        impl serde::Serialize for $name {
            fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error> {serde::Serialize::serialize(&$literal,s)}
        }
    };
    ($name:ident => $literal:literal) => {
        literal! {@visible(pub(super)) $name=>$literal}
    };
    (@visible($vis:vis) $name:ident => $literal:literal) => {
        #[derive(Debug)]
        $vis struct $name;
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
    (pub $name:ident ($tag:literal) { $($variant:ident => $wire:literal { $($field:ident : $ty:ty => $key:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_key:literal),* $(,)? })?),* $(,)? }) => {
        tagged! {@visible(pub) $name($tag){$($variant=>$wire{$($field:$ty=>$key),*} $(optional {$($optional:$optional_ty=>$optional_key),*})?),*}}
        impl serde::Serialize for $name {
            fn serialize<S:serde::Serializer>(&self,s:S)->Result<S::Ok,S::Error> {
                use serde::ser::SerializeMap as _;
                match self {$($name::$variant {$($field,)*$($($optional,)*)?}=>{
                    let mut map=s.serialize_map(None)?;map.serialize_entry($tag,$wire)?;
                    $(map.serialize_entry($key,$field)?;)*
                    $($(if let Presence::Present(value)=$optional {map.serialize_entry($optional_key,value)?;})*)?
                    map.end()
                }),*}
            }
        }
    };
    ($name:ident ($tag:literal) { $($variant:ident => $wire:literal { $($field:ident : $ty:ty => $key:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_key:literal),* $(,)? })?),* $(,)? } $(delegates { $($delegate:ident => $delegate_wire:literal : $delegate_ty:ty),* $(,)? })?) => {
        tagged! {@visible(pub(super)) $name($tag){$($variant=>$wire{$($field:$ty=>$key),*} $(optional {$($optional:$optional_ty=>$optional_key),*})?),*} $(delegates{$($delegate=>$delegate_wire:$delegate_ty),*})?}
    };
    (@visible($vis:vis) $name:ident ($tag:literal) { $($variant:ident => $wire:literal { $($field:ident : $ty:ty => $key:literal),* $(,)? } $(optional { $($optional:ident : $optional_ty:ty => $optional_key:literal),* $(,)? })?),* $(,)? } $(delegates { $($delegate:ident => $delegate_wire:literal : $delegate_ty:ty),* $(,)? })?) => {
        #[derive(Debug)]
        $vis enum $name { $($variant { $($field: $ty,)* $($( $optional: Presence<$optional_ty>, )*)? },)* $($($delegate($delegate_ty),)*)? }
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
