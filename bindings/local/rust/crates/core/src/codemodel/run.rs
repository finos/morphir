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
        //VerifiedIdentifier = (RunModifier::IsVerified | RunModifier::IsIdentifier).bits(),
    }
}

pub struct RunModifiers(FlagSet<RunModifier>);
impl RunModifiers {
    fn new(modifiers: impl Into<FlagSet<RunModifier>>) -> RunModifiers {
        RunModifiers(modifiers.into())
    }

    fn none() -> RunModifiers {
        RunModifiers::new(None)
    }
}

pub struct Run {
    pub text: String,
    modifiers: RunModifiers,
}

impl Run {
    pub fn new(text: String) -> Self {
        Self {
            text,
            modifiers: RunModifiers::none(),
        }
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

    #[test]
    fn test_run_modifiers() {
        let mut run = Run::new("test".to_string());
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
}
