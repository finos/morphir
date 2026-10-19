///|
/// Plan the existing generation backends from a bounded captured model. Logical
/// unit identity never becomes a filesystem path or changes during decoding.
pub fn Engine::plan_retained_generation(
  self : Engine,
  unit : @data.IRUnit,
  backend : String,
  output_root : String,
  options~ : Json = Json::object(Map([])),
  policy~ : BuildPolicy = SourceOnly,
  project~ : String = "generated",
) -> Plan raise {
  unit.validate()
  // The plan owns its accepted value. The maintained lossless codec snapshots
  // nested IR maps and opaque Ion context under the same default budgets.
  let registry = @data.Registry::new()
  let unit = registry.open_checkpoint("ion-binary", registry.checkpoint(unit))
  if !self.generators.contains(backend) {
    raise @configuration.Invalid("generation.unsupported_target: " + backend)
  }
  // Elm has no rich source-context sidecar. Reuse the established checked
  // semantic projection boundary before its generator can discard that context.
  if backend == "elm" {
    ignore(registry.encode("morphir-json", unit))
  }
  let files = Map::from_array([
    (
      "morphir.toml", "[project]\nname='retained'\nsource_directory='src'\n[frontend]\nlanguage='ir-json'\n",
    ),
    ("src/model.json", ""),
  ])
  let document = @configuration.from_json({
    "project": { "name": project },
    "workspace": { "out_dir": output_root },
    "pipeline": {
      "backend": backend,
      "validation": match policy {
        SourceOnly => "source-only"
        Required(_) => "required"
      },
      "target": match policy {
        SourceOnly => "wasm"
        Required(target) => target
      },
    },
    "backends": Json::object(Map::from_array([(backend, options)])),
  })
  let workspace = @workspace.discover(
    { files, directories: ["", "src"], },
    overlay=document,
  )
  let plan = self.plan(Host::memory(files), workspace, Request::new())
  { ..plan, jobs: plan.jobs.map(job => { ..job, retained_unit: Some(unit), }), }
}
