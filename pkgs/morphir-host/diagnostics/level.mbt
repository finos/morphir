///|
pub(all) enum DiagnosticLevel {
  Trace
  Debug
  Info
  Warn
  Error
  Fatal
  Off
} derive(Eq, Debug)

///|
pub extend DiagnosticLevel with Eq::{equal, not_equal}

///|
pub extend DiagnosticLevel with @debug.Debug::{to_repr}

///|
pub suberror InvalidLevel {
  InvalidLevel(String)
} derive(Debug)

///|
pub extend InvalidLevel with @debug.Debug::{to_repr}

///|
pub fn InvalidLevel::message(self : InvalidLevel) -> String {
  let InvalidLevel(value) = self
  "Unknown diagnostic log level '" +
  value +
  "'; expected trace, debug, info, warn, error, fatal or off"
}

///|
pub fn DiagnosticLevel::parse(
  value : String,
) -> DiagnosticLevel raise InvalidLevel {
  match value {
    "trace" => Trace
    "debug" => Debug
    "info" => Info
    "warn" => Warn
    "error" => Error
    "fatal" => Fatal
    "off" => Off
    _ => raise InvalidLevel(value)
  }
}

///|
pub fn DiagnosticLevel::name(self : DiagnosticLevel) -> String {
  match self {
    Trace => "trace"
    Debug => "debug"
    Info => "info"
    Warn => "warn"
    Error => "error"
    Fatal => "fatal"
    Off => "off"
  }
}

///|
pub fn DiagnosticLevel::minimum(self : DiagnosticLevel) -> @logging.Level? {
  match self {
    Trace => Some(@logging.Trace)
    Debug => Some(@logging.Debug)
    Info => Some(@logging.Information)
    Warn => Some(@logging.Warning)
    Error => Some(@logging.Error)
    Fatal => Some(@logging.Critical)
    Off => None
  }
}

///|
pub fn DiagnosticLevel::filter(
  self : DiagnosticLevel,
  logger : &@logging.Logger,
) -> &@logging.Logger {
  match self.minimum() {
    Some(level) => @logging.min_level(logger, level)
    None => @logging.null_logger()
  }
}

///|
/// Resolve a validated CLI level over the already layered configuration.
pub fn level_from_config(
  config : @lander_config.Config,
  selected_level? : DiagnosticLevel,
) -> DiagnosticLevel raise {
  match selected_level {
    Some(level) => level
    None =>
      DiagnosticLevel::parse(
        @lander_config.bind_or(config, "logging.level", "warn"),
      )
  }
}
