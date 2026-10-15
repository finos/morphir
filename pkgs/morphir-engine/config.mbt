///|
priv struct Config {
  mut frontend : String
  mut frontend_provider : String?
  mut frontend_profile : String?
  mut backend : String
  mut output : String
  mut package_name : String
  mut source : String
  mut inference : String
  transforms : Array[@scheme.Value]
}

///|
fn config_runtime(limits : @scheme.Limits) -> @scheme.Runtime raise {
  let runtime = @pipeline.new_runtime(limits~)
  for
    name in [
      "frontend", "frontend-provider", "frontend-profile", "backend", "output", "package-name",
      "source", "inference",
    ] {
    runtime.define_native(name, fn(_rt, args) raise {
      @scheme.arity(args, 1, name)
      @scheme.Record(Map::from_array([(name, @scheme.Text(args[0].as_text()))]))
    })
  }
  runtime.define_native("transform", fn(_rt, args) raise {
    @scheme.arity(args, 1, "transform")
    if !(args[0] is @scheme.Value::Closure(_) ||
      args[0] is @scheme.Value::Native(_)) {
      raise @scheme.Invalid("transform expects a procedure")
    }
    @scheme.Record(Map::from_array([("transform", args[0])]))
  })
  runtime.define_native("pipeline", fn(_rt, args) { @scheme.list(args) })
  runtime
}

///|
/// `origin` is the file of `script`, which an invalid `inference` value names.
fn Config::apply(
  self : Config,
  runtime : @scheme.Runtime,
  script : String,
  origin? : String = "",
) -> Unit raise {
  let entries = runtime.eval(script).to_array()
  for entry in entries {
    let fields = match entry {
      Record(fields) => fields
      _ => raise @scheme.Invalid("pipeline expects option records")
    }
    for name, value in fields {
      match name {
        "frontend" => self.frontend = value.as_text()
        "frontend-provider" =>
          self.frontend_provider = Some(
            source_constraint(value.as_text(), "provider"),
          )
        "frontend-profile" =>
          self.frontend_profile = Some(
            source_constraint(value.as_text(), "profile"),
          )
        "backend" => self.backend = value.as_text()
        "output" => {
          let output = normalize(value.as_text())
          if output == "" {
            raise @scheme.Invalid("Output directory must be nonempty")
          }
          self.output = output
        }
        "package-name" => self.package_name = value.as_text()
        "source" => self.source = normalize(value.as_text())
        "transform" => self.transforms.push(value)
        "inference" => {
          let text = value.as_text()
          let _ = inference_mode(text) catch {
            @configuration.Invalid(message) =>
              raise @configuration.Invalid(
                if origin == "" {
                  message
                } else {
                  message + " (set in " + origin + ")"
                },
              )
            e => raise e
          }
          self.inference = text
        }
        _ => raise @scheme.Invalid("Unknown pipeline option: " + name)
      }
    }
  }
}
