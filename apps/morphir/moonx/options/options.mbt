///|
pub(all) enum OutputFormat {
  Human
  MachineJson
}

///|
pub(all) enum Request {
  Help
  Forward(Array[String])
}

///|
pub struct Options {
  priv format : OutputFormat
  priv request : Request
}

///|
pub suberror OptionsError {
  InvalidControls(format~ : OutputFormat, message~ : String)
}

///|
pub fn Options::format(self : Options) -> OutputFormat {
  self.format
}

///|
pub fn Options::request(self : Options) -> Request {
  match self.request {
    Help => Help
    Forward(args) => Forward(args.copy())
  }
}

///|
/// Own only leading launcher controls. Keep the application tail opaque,
/// including delimiters and empty values. Leading --json also selects launcher
/// reporting, but stays in the exact argument array passed to Morphir.
pub fn parse(args : Array[String]) -> Options raise OptionsError {
  let controls : Array[String] = []
  let forwarded : Array[String] = []
  let mut index = 0
  while index < args.length() {
    let input = args[index]
    if input == "--moonx-forward" {
      controls.push(input)
      index += 1
      break
    }
    if input == "--json" {
      controls.push(input)
      forwarded.push(input)
    } else if input.has_prefix("--moonx-") {
      controls.push(input)
    } else {
      break
    }
    index += 1
  }
  forwarded.append(args[index:])
  let format : OutputFormat = if controls.contains("--json") ||
    controls.contains("--moonx-json") {
    MachineJson
  } else {
    Human
  }
  let command = @argparse.Command("morphir-moonx", disable_help_flag=true, flags=[
    @argparse.FlagArg("json"),
    @argparse.FlagArg("moonx-json"),
    @argparse.FlagArg("moonx-help"),
    @argparse.FlagArg("moonx-forward"),
  ])
  let parsed = command.parse(argv=controls) catch {
    error => raise InvalidControls(format~, message=error.to_string())
  }
  {
    format: if parsed.flags.get("json").unwrap_or(false) ||
      parsed.flags.get("moonx-json").unwrap_or(false) {
      MachineJson
    } else {
      Human
    },
    request: if parsed.flags.get("moonx-help").unwrap_or(false) {
      Help
    } else {
      Forward(forwarded)
    },
  }
}
