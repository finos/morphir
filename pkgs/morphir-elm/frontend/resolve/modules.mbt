///|
/// One parsed module of the project. `name` is the dotted module name, one element per segment. `path` is the
/// source path relative to the source directory.
pub(all) struct ParsedModule {
  name : Array[String]
  path : String
  file : @ast.File
} derive(Eq, Debug)

///|
pub extend ParsedModule with Eq::{equal, not_equal}

///|
pub extend ParsedModule with @debug.Debug::{to_repr}

///|
pub fn ParsedModule::header(self : ParsedModule) -> @ast.DefaultModuleData {
  match self.file.module_definition.value {
    NormalModule(data) | PortModule(data) => data
    EffectModule(data) =>
      { module_name: data.module_name, exposing_list: data.exposing_list, }
  }
}

///|
/// The modules that this module imports, by dotted name.
pub fn ParsedModule::imports(self : ParsedModule) -> Array[Array[String]] {
  self.file.imports
  .iter()
  .map(i => i.value.module_name.value.to_owned())
  .collect()
}
