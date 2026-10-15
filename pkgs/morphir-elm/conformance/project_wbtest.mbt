///|
/// An Elm parity project: its `morphir.json` settings, its Elm sources and the `morphir-elm make` 2.100.0
/// output. `parity_projects` in the generated `parity_data_wbtest.mbt` lists them.
priv struct ParityProject {
  name : String
  package_name : String
  exposed : Array[String]
  sources : Array[(String, String)] // path relative to the source directory, content
  expected : String // morphir-elm make output
}
