///|
priv struct Checkpoint {
  input : DataFormat?
  output : DataFormat
  codecs : @data.Registry
}

///|
pub(all) struct ContentArtifact {
  path : String
  source : String
  content : @data.Content
  format : String
}

///|
pub(all) struct ContentReport {
  artifacts : Array[ContentArtifact]
  projects : Array[LibraryProject]
  diagnostics : Array[Diagnostic]
  warnings : Array[Diagnostic]
  processed : Int32
}

///|
pub fn ContentReport::successful(self : ContentReport) -> Bool {
  self.diagnostics.is_empty()
}

///|
pub(all) struct BoundarySelection {
  source : String
  unit_id : String
  input_format : String
  output_format : String
  profile : String?
  read_bytes : Bool
  write_bytes : Bool
}

///|
fn Engine::data_format(self : Engine, name : String) -> DataFormat raise {
  match self.data_formats.get(name) {
    Some(format) => format
    None => raise @configuration.Invalid("data.unknown_codec: " + name)
  }
}

///|
/// Describe file selection and transport independently of the registered codec.
pub(all) struct DataFormat {
  codec : String
  extensions : Array[String]
  suffix : String
  binary : Bool
}

///|
pub fn Engine::register_data_format(
  self : Engine,
  name : String,
  format : DataFormat,
) -> Unit raise {
  if name == "" ||
    self.data_formats.contains(name) ||
    self.frontends.contains(name) ||
    self.source_providers
    .values()
    .any(p => p.languages.any(l => l.id.to_string() == name)) ||
    name == "ir-json" {
    raise @configuration.Invalid("data.format_conflict: " + name)
  }
  fn valid_suffix(suffix : String) -> Bool {
    suffix.length() > 1 &&
    suffix.has_prefix(".") &&
    !suffix.contains("/") &&
    !suffix.contains("\\") &&
    !suffix.contains(":") &&
    !suffix.contains("\u0000")
  }
  if format.codec == "" ||
    !valid_suffix(format.suffix) ||
    format.extensions.is_empty() ||
    !format.extensions.all(valid_suffix) {
    raise @configuration.Invalid("data.invalid_format: " + name)
  }
  self.data_formats[name] = { ..format, extensions: format.extensions.copy(), }
}

///|
pub fn Plan::boundaries(self : Plan) -> Array[BoundarySelection] {
  let result = []
  for job in self.jobs {
    for source in job.paths {
      result.push({
        source,
        unit_id: match job.retained_unit {
          Some(unit) => unit.id
          None =>
            stem(
              if job.source_root == "" {
                source
              } else {
                source[job.source_root.length() + 1:].to_owned()
              },
            )
        },
        input_format: match job.boundary {
          Some(b) =>
            match b.input {
              Some(input) => input.codec
              None => job.settings.frontend
            }
          None => job.settings.frontend
        },
        output_format: match job.boundary {
          Some(b) =>
            if job.generator is Some(_) {
              job.settings.backend
            } else {
              b.output.codec
            }
          None => job.settings.backend
        },
        profile: match job.boundary {
          Some(_) => Some(@data.PROFILE)
          None => None
        },
        read_bytes: job.read_bytes,
        write_bytes: match job.boundary {
          Some(b) =>
            match job.generator {
              Some(g) => g.write_bytes
              None => b.output.binary
            }
          None => false
        },
      })
    }
  }
  result
}

///|
pub fn Plan::requires_byte_read(self : Plan) -> Bool {
  self.jobs.any(job => job.read_bytes)
}

///|
pub fn Plan::requires_byte_write(self : Plan) -> Bool {
  self.jobs.any(job => {
    job.unit_backend ||
    (match job.boundary {
      Some(boundary) =>
        match job.generator {
          Some(g) => g.write_bytes
          None => boundary.output.binary
        }
      None => false
    })
  })
}

///|
/// The existing text executor cannot represent a binary checkpoint result.
pub fn Engine::execute(
  self : Engine,
  plan : Plan,
  host : Host,
  cancelled~ : () -> Bool = fn() { false },
) -> Report {
  if plan.requires_byte_read() || plan.requires_byte_write() {
    return {
      artifacts: [],
      processed: 0,
      diagnostics: [
        {
          path: "",
          stage: "capability",
          message: "host.bytes_required: Binary plans require execute_content",
          details: None,
          problem: None,
        },
      ],
    }
  }
  self
  .execute_content(
    plan,
    fn(path, _) raise { @data.Text((host.read)(path)) },
    cancelled~,
  )
  .text_report()
}

///|
pub fn ContentReport::text_report(self : ContentReport) -> Report {
  let artifacts = []
  for artifact in self.artifacts {
    let content = match artifact.content {
      Text(text) => text
      Binary(_) =>
        return {
          artifacts: [],
          processed: 0,
          diagnostics: self.diagnostics +
          [
            {
              path: artifact.path,
              stage: "capability",
              message: "host.byte_write_required: Binary artifacts cannot be represented by a text report",
              details: None,
              problem: None,
            },
          ],
        }
    }
    artifacts.push({ path: artifact.path, source: artifact.source, content, })
  }
  { artifacts, diagnostics: self.diagnostics, processed: self.processed, }
}
