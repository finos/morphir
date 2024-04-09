use flagset::{flags, FlagSet};
#[cfg(feature = "serde")]
use serde_repr::{Deserialize_repr, Serialize_repr};

flags! {
    #[repr(u8)]
    #[cfg_attr(feature="serde", derive(Deserialize_repr, Serialize_repr))]
    pub enum RunModifier: u8 {
        IsVerified,
        IsCanonical,
        IsIdentifier,
        ContainsSymbol,
        //VerifiedIdentifier = (RunModifier::IsVerified | RunModifier::IsIdentifier).bits(),
    }
}

pub struct RunModifiers(FlagSet<RunModifier>);
impl RunModifiers {
    
    pub fn new(modifiers: impl Into<FlagSet<RunModifier>>) -> RunModifiers {
        RunModifiers(modifiers.into())
    }

    pub fn none() -> RunModifiers {
        RunModifiers::new(None)
    }
}

pub struct Run {
    text: String,
    modifiers: RunModifiers,
}


impl Run {
    pub fn new(text: &str) -> Self {
        Self {
            text: text.to_string(),
            modifiers: RunModifiers::none(),
        }
    }

    pub fn unverified(text: &str) -> Self {
        Self { text: text.to_string(), modifiers: RunModifiers::none() }
    }

    pub fn text(&self) -> &str {
        &self.text
    }

    pub fn is_verified(&self) -> bool {
        self.modifiers.0.contains(RunModifier::IsVerified)
    }

    pub fn is_canonical(&self) -> bool {
        self.modifiers.0.contains(RunModifier::IsCanonical)
    }

    pub fn is_identifier(&self) -> bool {
        self.modifiers.0.contains(RunModifier::IsIdentifier)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use proptest::prelude::*;

    #[test]
    fn test_run_modifiers() {
        let mut run = Run::new("test");
        assert!(!run.is_verified());
        assert!(!run.is_canonical());
        assert!(!run.is_identifier());

        run.modifiers = RunModifiers::new(RunModifier::IsVerified);
        assert!(run.is_verified());
        assert!(!run.is_canonical());
        assert!(!run.is_identifier());

        run.modifiers = RunModifiers::new(RunModifier::IsCanonical);
        assert!(!run.is_verified());
        assert!(run.is_canonical());
        assert!(!run.is_identifier());

        run.modifiers = RunModifiers::new(RunModifier::IsIdentifier);
        assert!(!run.is_verified());
        assert!(!run.is_canonical());
        assert!(run.is_identifier());
    }

    proptest! {
        #[test]
        fn identifiers_should_have_approptiate_flags(text in "[:alpha:_][:alpha:0-9_]{0,255}") {
            let run = Run::new(text.as_str());
            if run.text.starts_with('_') {
                assert!(run.is_identifier());
            } else {
                assert!(!run.is_identifier());
            }
        }
    }
}
