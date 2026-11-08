//! Golden source for the MEP 0.2.0-draft.1 model operation tests.

/// A person in the domain.
pub struct Person {
    pub name: String,
    pub age: i64,
}

/// The state of a decision.
pub enum Decision {
    Pending,
    Accepted(Person),
    Rejected { reason: String },
}

pub type Score = (String, i64);

/// The larger of two values, or zero when they are equal.
pub fn select(a: i64, b: i64) -> i64 {
    if a == b { 0 } else if a > b { a } else { b }
}

pub fn amount(value: Option<i64>) -> i64 {
    match value {
        Some(amount) => amount,
        None => 0,
    }
}
