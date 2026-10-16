// The logical path grammar. A path names one Value, Pattern or Type node of a declaration, and does not depend on whether the node is written in its compact or its expanded form. It is the grammar of inference diagnostics and of logical_nodes.
//
// | Child                     | Step                                                  |
// | ------------------------- | ----------------------------------------------------- |
// | a declaration's body      | `/body`                                               |
// | `Apply` function          | `/function`                                           |
// | `Apply` argument          | `/argument`                                           |
// | `Lambda`                  | `/pattern`, `/body`                                   |
// | `LetDefinition`           | `/definition/body`, `/in`                             |
// | `LetRecursion`            | `/definitions/<name>/body`, `/in`                     |
// | `Destructure`             | `/pattern`, `/value`, `/in`                           |
// | `IfThenElse`              | `/condition`, `/then`, `/else`                        |
// | `PatternMatch`            | `/subject`, `/cases/<i>/pattern`, `/cases/<i>/body`   |
// | `Tuple`, `List`           | `/items/<i>`                                          |
// | `Record`                  | `/fields/<name>`                                      |
// | `Field`                   | `/record`                                             |
// | `UpdateRecord`            | `/record`, `/fields/<name>`                           |
// | `AsPattern`               | `/pattern`                                            |
// | `TuplePattern`            | `/items/<i>`                                          |
// | `ConstructorPattern`      | `/args/<i>`                                           |
// | `HeadTailPattern`         | `/head`, `/tail`                                      |
// | A signature input type    | `/inputs/<name>`                                      |
// | A signature output type   | `/output`                                             |
// | Hole expected type        | `/expected`                                           |
// | Type Function             | `/parameter`, `/return`                               |
// | Type Reference            | `/args/<i>`                                           |
// | Type Tuple                | `/items/<i>`                                          |
// | Type Record, ExtensibleRecord | `/fields/<name>`                                  |
//
// A declaration's root is `value:<package>:<module>#<name>`. `<name>` is a canonical name and `<i>` is a
// 0-based index.

///|
/// The root path of the value declaration `name`.
pub fn value_root(name : @ir.FQName) -> String {
  "value:" + name.to_canonical()
}

///|
fn step(path : String, child : String) -> String {
  path + "/" + child
}

///|
/// The body of a declaration, a lambda or a definition.
pub fn path_body(path : String) -> String {
  step(path, "body")
}

///|
pub fn path_function(path : String) -> String {
  step(path, "function")
}

///|
pub fn path_argument(path : String) -> String {
  step(path, "argument")
}

///|
/// The pattern of a `Lambda`, a `Destructure` or an `AsPattern`.
pub fn path_pattern(path : String) -> String {
  step(path, "pattern")
}

///|
/// The definition of a `LetDefinition`. Its body is at `path_body` of this path.
pub fn path_definition(path : String) -> String {
  step(path, "definition")
}

///|
/// One definition of a `LetRecursion`. Its body is at `path_body` of this path.
pub fn path_definitions(path : String, name : @ir.Name) -> String {
  step(path, "definitions/" + name.to_canonical())
}

///|
pub fn path_definitions_body(path : String, name : @ir.Name) -> String {
  path_body(path_definitions(path, name))
}

///|
pub fn path_in(path : String) -> String {
  step(path, "in")
}

///|
pub fn path_value(path : String) -> String {
  step(path, "value")
}

///|
pub fn path_condition(path : String) -> String {
  step(path, "condition")
}

///|
pub fn path_then(path : String) -> String {
  step(path, "then")
}

///|
pub fn path_else(path : String) -> String {
  step(path, "else")
}

///|
pub fn path_subject(path : String) -> String {
  step(path, "subject")
}

///|
pub fn path_case_pattern(path : String, i : Int32) -> String {
  step(path, "cases/\{i}/pattern")
}

///|
pub fn path_case_body(path : String, i : Int32) -> String {
  step(path, "cases/\{i}/body")
}

///|
/// An item of a `Tuple`, a `List` or a `TuplePattern`.
pub fn path_item(path : String, i : Int32) -> String {
  step(path, "items/\{i}")
}

///|
/// A field of a `Record` or an `UpdateRecord`.
pub fn path_field(path : String, name : @ir.Name) -> String {
  step(path, "fields/" + name.to_canonical())
}

///|
/// The record of a `Field` or an `UpdateRecord`.
pub fn path_record(path : String) -> String {
  step(path, "record")
}

///|
pub fn path_arg(path : String, i : Int32) -> String {
  step(path, "args/\{i}")
}

///|
pub fn path_head(path : String) -> String {
  step(path, "head")
}

///|
pub fn path_tail(path : String) -> String {
  step(path, "tail")
}

///|
/// One input type of a signature.
pub fn path_input(path : String, name : @ir.Name) -> String {
  step(path, "inputs/" + name.to_canonical())
}

///|
/// The output type of a signature.
pub fn path_output(path : String) -> String {
  step(path, "output")
}

///|
/// The declared type of a `Hole`.
pub fn path_expected(path : String) -> String {
  step(path, "expected")
}

///|
/// The parameter type of a type `Function`.
pub fn path_parameter(path : String) -> String {
  step(path, "parameter")
}

///|
/// The return type of a type `Function`.
pub fn path_return(path : String) -> String {
  step(path, "return")
}
