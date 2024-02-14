#![allow(dead_code)]
pub mod name;

pub use name::Name;

// Goals/capabilities of new IR/code model
// 1. Naming - simplify and/or unify naming concepts a bit
// . 1.1. For example represent by URI or URN but make canonical string representation easier
// 2. Annotations via RDF-like Graph - support custom annotations and metadata via the metadata
// 3. Support a WASM backend
// 4. Unify the graph eliminate need for repetitive IR/MDM/RTValue concepts
// 5. Revisit Specification/Definition distinction and perhaps just have definition be an optional part of spec

pub enum Node {}

pub struct Triple {
    subject: Node,
    predicate: Node, //TODO: This shouuld be something else Node-like but somewhat restricted
    object: Node,
}

pub struct Graph {
    triples: Vec<Triple>,
}

pub enum Data {
    UInt32(u32),
    UInt64(u64),
    Int32(i32),
    Int64(i64),

    Boolean(bool),
    String(String),
}

pub enum Value {
    Data(Data),
}
