///|
/// Where a value declaration of the output comes from: the Elm spelling, the source path (as given in
/// `ElmSource.path`), the range of the declaration's name and the lifted parameters with their ranges.
pub(all) struct DeclarationOrigin {
  module_name : @ir.Path
  name : @ir.Name
  source_name : String
  path : String
  span : @ir.SourceLocation
  parameters : Array[(String, @ir.SourceLocation)]
} derive(Eq, Debug)

///|
pub extend DeclarationOrigin with Eq::{equal, not_equal}

///|
pub extend DeclarationOrigin with @debug.Debug::{to_repr}

///|
/// The IR of a project and the origins of its value declarations, sorted by module path then name.
pub(all) struct ProjectOutput {
  ir : @ir.IRFile
  origins : Array[DeclarationOrigin]
}
