///|
fn main {
  let options = @options.parse(@env.args()[1:].to_owned()) catch {
    InvalidControls(format~, message~) => {
      report_failure(format, 2U, "invalid_arguments", message)
      return @sys.exit(2)
    }
  }
  match options.request() {
    Help =>
      match options.format() {
        Human => println(launcher_help)
        MachineJson => println(help_document().stringify())
      }
    Forward(arguments) => {
      let launch = @launcher.NodeLaunch::new(
        packaged_payload(),
        @launcher.Arguments::parse(arguments),
      ) catch {
        error => {
          report_failure(
            options.format(),
            1U,
            "moonx.payload_unavailable",
            error.to_string(),
          )
          return @sys.exit(1)
        }
      }
      @driver.run(Node(launch), completed=outcome => {
        match options.format() {
          MachineJson =>
            if startup_document(outcome) is Some(document) {
              eprintln(document.stringify())
            }
          Human =>
            if startup_failure(outcome) is Some((code, message)) {
              report_failure(
                Human,
                outcome.selected_status().bits(),
                code,
                message,
              )
            }
        }
        // Forwarded commands own stdout, including JSON and framed protocols.
        // Keep startup and cleanup reports on the separate diagnostic channel.
        for failure in outcome.finalization_failures() {
          let message = match failure {
            PayloadCleanup(error) | Finalizer(error) => error.to_string()
          }
          eprintln("Morphir Moonx finalization failed: " + message)
        }
      })
    }
  }
}
