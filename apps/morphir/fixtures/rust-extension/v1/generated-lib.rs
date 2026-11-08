pub mod models {
    ///The state of a decision.
    pub enum Decision {
        Pending,
        Accepted(crate::models::Person),
        Rejected(::std::string::String),
    }
    ///A person in the domain.
    pub struct Person {
        pub name: ::std::string::String,
        pub age: i64,
    }
    pub type Score = (::std::string::String, i64);
    ///The larger of two values, or zero when they are equal.
    pub fn select(a: i64, b: i64) -> i64 {
        if (a) == (b) { 0i64 } else { if (a) > (b) { a } else { b } }
    }
    pub fn amount(value: ::std::option::Option<i64>) -> i64 {
        match value {
            ::std::option::Option::Some(__morphir_binding_1) => __morphir_binding_1,
            ::std::option::Option::None => 0i64,
        }
    }
}
