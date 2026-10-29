///|
fn worksheet_command(cli : Cli, mode : OutputMode) -> Int32 raise {
  let path = value(cli, "path")
  if path == "" {
    raise @config.Invalid("worksheet.input_required")
  }
  if !@platform.interruption_supported() {
    raise @config.Invalid("worksheet.interruption_unavailable")
  }
  let timeout = build_timeout(value(cli, "timeout", fallback="120000"))
  let revision = @string.parse_int(value(cli, "source-revision", fallback="0")) catch {
    _ => raise @config.Invalid("worksheet.invalid_revision")
  }
  let cancel_file = value(cli, "cancel-file")
  @platform.interruption_start()
  defer @platform.interruption_stop()
  let source = worksheet_capture(
    @platform.read_input(path, 1048576),
    value(cli, "source-id", fallback="source"),
    revision,
  )
  let started = @platform.monotonic_seconds()
  let report = source.evaluate(interrupted=fn() {
    if @platform.interruption_requested() ||
      (cancel_file != "" && (@platform.kind(cancel_file) catch { _ => 1 }) != 0) {
      Some(@worksheet.Cancelled)
    } else if (@platform.monotonic_seconds() - started) * 1000.0 >=
      timeout.to_double() {
      Some(@worksheet.TimedOut)
    } else {
      None
    }
  })
  match mode {
    JSON => println(report.to_json().stringify())
    JSONLines => {
      let encoded = report.to_json()
      guard encoded is Object(fields) &&
        fields.get("observations") is Some(Array(rows)) else {
        abort("canonical worksheet observation inventory")
      }
      for row in rows {
        emit_record("observation", row)
      }
      emit_record("result", encoded)
    }
    Human => {
      for row in report.observations() {
        println(row.expression() + "\t" + row.outcome().to_json().stringify())
      }
      if !report.successful() {
        @platform.stderr(report.completion().to_json().stringify() + "\n")
      }
    }
  }
  worksheet_status(report)
}

///|
fn worksheet_capture(
  bytes : Bytes,
  id : String,
  revision : Int32,
) -> @worksheet.WorksheetRequest raise {
  if bytes.length() > 1048576 {
    raise @config.Invalid("worksheet.input_limit")
  }
  let text = @utf8.decode(bytes[:]) catch {
    _ => raise @config.Invalid("worksheet.invalid_utf8")
  }
  @worksheet.WorksheetRequest::new(
    @worksheet.CapturedWorksheetSource::new(
      @worksheet.WorksheetId::parse(id),
      @worksheet.SourceRevision::new(revision),
      text,
    ),
  )
}

///|
fn worksheet_status(report : @worksheet.WorksheetReport) -> Int32 {
  if report.completion() is Cancelled {
    130
  } else if report.successful() {
    0
  } else {
    1
  }
}
