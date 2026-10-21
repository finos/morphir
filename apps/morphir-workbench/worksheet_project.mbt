///|
/// The host prepares a fresh bounded worksheet runtime from the captured
/// current project. This callback is local adapter behavior, not wire authority.
fn prepare_worksheet_project(
  engine : @engine.Engine,
  request : Json,
  runtime : @scheme.Runtime,
) -> Unit raise {
  guard @wire.optional(request, "workspace") is Some(value) else { return }
  let files = @workspace_files.Files::from_json(value)
  let workspace = files.discover()
  if workspace.projects.is_empty() {
    return
  }
  let selector = optional_text(request, "projectPath").unwrap_or("")
  if selector == "" {
    raise @config.Invalid("The worksheet requires a current project")
  }
  let host = @engine.Host::memory(files.tree().files)
  let plan = engine.plan(host, workspace, {
    ..@engine.Request::new(),
    selector,
    // Evaluate the configured source/transforms through Scheme, independently of its generation target.
    overlay: @config.parse(
      "[pipeline]\nvalidation='source-only'\nbackend='scheme'\ncheckpoint_format='ion-binary'\n",
    ),
  })
  let libraries : Array[@ir.IRFile] = []
  let report = engine.execute_content(
    plan,
    fn(path, _) raise {
      files.content(path).unwrap_or(@data.Text((host.read)(path)))
    },
    on_unit=unit => libraries.push(unit.unit.distribution),
  )
  if !report.successful() || libraries.is_empty() {
    raise @config.Invalid(
      report.diagnostics
      .get(0)
      .map(d => d.message)
      .unwrap_or("The current project produced no compiled model"),
    )
  }
  @backend.install(runtime)
  let public_values : Array[(@ir.FQName, Int32)] = []
  for library in libraries {
    @backend.link_file(runtime, library)
    ignore(runtime.eval(@backend.emit_file(library)))
    match library.distribution {
      Library(package_name, _, package_def)
      | Application(package_name, _, package_def, _) =>
        for module_name, module_def in package_def.modules {
          if module_def.access is Private {
            continue
          }
          for local_name, value in module_def.value.values {
            if value.access is Private {
              continue
            }
            if value.value.value.to_specification() is Some(specification) {
              public_values.push(
                (
                  { package_name, module_name, local_name, },
                  specification.inputs.length(),
                ),
              )
            }
          }
        }
      Specs(_, _, _) => ()
    }
  }
  for (name, arity) in public_values {
    let short_name = name.local_name.to_canonical()
    let aliases = [
      name.to_canonical(),
      name.module_name.to_canonical() + "." + short_name,
    ]
    let unique = public_values
      .filter(value => value.0.local_name == name.local_name)
      .length() ==
      1
    let unused = try {
      ignore(runtime.lookup(short_name))
      false
    } catch {
      _ => true
    }
    if unique && unused {
      aliases.push(short_name)
    }
    for binding in aliases {
      runtime.define_native(binding, fn(runtime, arguments) raise {
        @scheme.arity(arguments, arity, binding)
        @backend.call_entry(runtime, name, arguments)
      })
    }
  }
}
