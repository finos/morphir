///|
pub(all) enum DiagnosticFiles {
  Disabled
  Enabled(@rolling.FileFormat)
} derive(Eq, Debug)

///|
pub extend DiagnosticFiles with Eq::{equal, not_equal}

///|
pub extend DiagnosticFiles with @debug.Debug::{to_repr}

///|
pub(all) struct Settings {
  level : DiagnosticLevel
  files : DiagnosticFiles
} derive(Eq, Debug)

///|
pub extend Settings with Eq::{equal, not_equal}

///|
pub extend Settings with @debug.Debug::{to_repr}

///|
pub suberror InvalidFileFormat {
  InvalidFileFormat(String)
} derive(Debug)

///|
pub extend InvalidFileFormat with @debug.Debug::{to_repr}

///|
pub fn InvalidFileFormat::message(self : InvalidFileFormat) -> String {
  let InvalidFileFormat(value) = self
  "Unknown diagnostic file format '" + value + "'; expected text or json-lines"
}

///|
/// Bind only diagnostic settings; telemetry owns its separate options and files.
pub fn Settings::from_config(
  configuration : @lander_config.Config,
  selected_level? : DiagnosticLevel,
) -> Settings raise {
  let level = level_from_config(configuration, selected_level?)
  let enabled : Bool = @lander_config.bind_or(
    configuration, "logging.file.enabled", false,
  )
  let files = if enabled {
    let format : String = @lander_config.bind_or(
      configuration, "logging.file.format", "text",
    )
    Enabled(
      match format {
        "text" => @rolling.Text
        "json-lines" => @rolling.JsonLines
        _ => raise InvalidFileFormat(format)
      },
    )
  } else {
    Disabled
  }
  { level, files, }
}

///|
/// The caller grants the workspace's `.morphir/logs` directory. The published
/// session owns queuing, file writes, rolling, retention and final draining.
pub fn Settings::session(
  self : Settings,
  directory : @sinks.LogDirectory,
) -> @sinks.SessionSettings raise {
  guard self.level.minimum() is Some(minimum) else {
    return @sinks.SessionSettings::new()
  }
  let files = match self.files {
    Disabled => []
    Enabled(format) =>
      [
        @sinks.FileSink::new(
          directory,
          @rolling.LogFileStem::parse("morphir-diagnostics"),
          format~,
          policy=DailyAndSize(@rolling.FileByteLimit::bytes(10485760L)),
          retention=KeepNewest(@rolling.RetainedFileCount::count(31)),
          minimum~,
          json_properties=NamedObject,
        ),
      ]
  }
  @sinks.SessionSettings::new(
    console=@sinks.ConsoleSink::new(stream=StandardError, minimum~),
    files~,
  )
}
