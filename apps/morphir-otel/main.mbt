///|
suberror AdapterError {
  Invalid(String)
}

///|
fn adapter_command() -> @argparse.Command {
  @argparse.Command(
    "morphir-otel",
    about="Export an explicit bounded Ion batch to an HTTP telemetry endpoint",
    disable_help_flag=true,
    positionals=[
      @argparse.PositionArg(
        "ENDPOINT",
        num_args=@argparse.ValueRange::single(),
      ),
      @argparse.PositionArg(
        "PROTOCOL",
        num_args=@argparse.ValueRange::single(),
      ),
      @argparse.PositionArg(
        "TIMEOUT",
        num_args=@argparse.ValueRange::single(),
      ),
    ],
  )
}

///|
fn adapter_arguments(argv : ArrayView[String]) -> @argparse.Matches raise {
  // All three operands are application data. Preserve literal delimiters and
  // control spellings while the library validates their exact arity.
  adapter_command().parse(argv=["--"] + argv.to_owned(), env=Map([]))
}

///|
fn field(value : @ion.IonValue, name : String) -> @ion.IonValue raise {
  guard value.kind() is Struct(fields) else { raise Invalid("record required") }
  let found = fields.filter(f => f.name.text() == Some(name))
  guard found.length() == 1 else {
    raise Invalid("missing or duplicate " + name)
  }
  found[0].value
}

///|
fn text(value : @ion.IonValue) -> String raise {
  guard value.kind() is String(s) else { raise Invalid("string required") }
  s
}

///|
fn number(value : @ion.IonValue) -> Double raise {
  guard value.kind() is Float(n) && !n.is_inf() && !n.is_nan() else {
    raise Invalid("finite float required")
  }
  n
}

///|
fn array(value : @ion.IonValue) -> Array[@ion.IonValue] raise {
  guard value.kind() is List(values) else { raise Invalid("list required") }
  values
}

///|
fn context(record : @ion.IonValue, key : String) -> @common.SpanContext raise {
  let trace = @common.TraceId::from_hex(text(field(record, "trace_id")))
  let span = @common.SpanId::from_hex(text(field(record, key)))
  guard trace is Some(t) && span is Some(s) else {
    raise Invalid("invalid trace context")
  }
  @common.SpanContext::new(t, s, trace_flags=@common.TraceFlags::new(1U))
}

///|
async fn main {
  try {
    let args = adapter_arguments(@env.args()[1:])
    let endpoint = args.values["ENDPOINT"][0]
    guard endpoint.has_prefix("http://") || endpoint.has_prefix("https://") else {
      raise Invalid("explicit HTTP endpoint required")
    }
    let protocol = match args.values["PROTOCOL"][0] {
      "http/json" => @otlp.HttpJson
      "http/protobuf" => @otlp.HttpBinary
      _ => raise Invalid("unsupported protocol")
    }
    let timeout = @string.parse_int(args.values["TIMEOUT"][0])
    guard timeout > 0 && timeout <= 5000 else {
      raise Invalid("invalid flush allowance")
    }
    // Bound before parsing. No SDK globals, implicit endpoint, resource detector,
    // background threads or exporter chosen by the portable engine.
    let buffer = @buffer.Buffer::Buffer()
    while @stdio.stdin.read_some(max_len=65536) is Some(bytes) {
      guard buffer.length() + bytes.length() <= 4194304 else {
        raise Invalid("batch limit")
      }
      buffer.write_bytes(bytes[:])
    }
    let records = @binary.read_binary(buffer.to_bytes()[:])
    guard records.length() <= 2049 else { raise Invalid("record limit") }
    let scope = @common.InstrumentationScope::builder("finos/morphir-execution")
      .with_version("0.1.0")
      .build()
    let resource = @resource.Resource::new([
      @common.KeyValue::new("service.name", String("morphir")),
    ])
    let starts : Map[String, Int64] = Map([])
    let spans : Array[@trace.SpanData] = []
    let logs : Array[@logs.LogRecord] = []
    let meter_provider = @metrics.SdkMeterProvider::builder()
      .with_resource(resource)
      .build()
    let meter = meter_provider.meter(
      "finos/morphir-execution",
      version=Some("0.1.0"),
    )
    let counter = meter
      .counter("morphir.operations")
      .with_unit("{operation}")
      .build()
    let duration_counter = meter
      .f64_counter("morphir.duration.sum")
      .with_unit("s")
      .build()
    for record in records {
      let profile = text(field(record, "profile"))
      if profile == "morphir-metrics-v1" {
        for row in array(field(record, "dimensions")) {
          let attrs = ["stage", "target", "provider", "outcome"].map(k => {
            @common.KeyValue::new("morphir." + k, String(text(field(row, k))))
          })
          let count = number(field(row, "count")).to_int64()
          let sum = number(field(row, "duration_seconds_sum"))
          counter.add(count, attributes=attrs[:])
          duration_counter.add(sum, attributes=attrs[:])
        }
        continue
      }
      guard profile == "morphir-observation-v1" else {
        raise Invalid("unsupported profile")
      }
      let stage = text(field(record, "stage"))
      let signal = text(field(record, "signal"))
      let wall = (number(field(record, "wall_seconds")) * 1000000000.0).to_int64()
      let duration = number(field(record, "duration_seconds"))
      let id = text(field(record, "span_id"))
      if signal == "started" {
        starts[id] = wall
        continue
      }
      let attrs = [
        @common.KeyValue::new("morphir.stage", String(stage)),
        @common.KeyValue::new("morphir.signal", String(signal)),
      ]
      let correlation = field(record, "correlation")
      if !correlation.is_null() {
        for key in ["target", "call_id", "attempt_id", "lease_id"] {
          attrs.push(
            @common.KeyValue::new(
              "morphir." + key,
              String(text(field(correlation, key))),
            ),
          )
        }
      }
      let ctx = if id == "" { None } else { Some(context(record, "span_id")) }
      logs.push(
        @logs.LogRecord::new(
          String(stage + "." + signal),
          timestamp_unix_nano=wall,
          observed_timestamp_unix_nano=wall,
          trace_context=ctx,
          attributes=attrs.map(@logs.KeyValue::from_common)[:],
          resource~,
          instrumentation_scope=scope,
        ),
      )
      if ctx is Some(span_context) {
        let start = starts
          .get(id)
          .unwrap_or(wall - (duration * 1000000000.0).to_int64())
        let parent = if text(field(record, "parent_id")) == "" {
          None
        } else {
          Some(context(record, "parent_id"))
        }
        let provider = @trace.SdkTracerProvider::builder()
          .with_resource(resource)
          .with_id_generator(
            @trace.IdGenerator::new(fn() { span_context.trace_id() }, fn() {
              span_context.span_id()
            }),
          )
          .build()
        let tracer = provider.tracer(
          "finos/morphir-execution",
          version=Some("0.1.0"),
        )
        let parent_context = match parent {
          Some(p) => @context.Context::empty().with_span_context(p)
          None => @context.Context::empty()
        }
        let span = tracer.start(
          "morphir." + stage,
          parent_context~,
          attributes=attrs[:],
          start_time_unix_nano=start,
        )
        span.set_status(
          if signal == "failed" || signal == "cancelled" {
            @trace.Status::error(description=Some(signal))
          } else {
            @trace.Status::ok()
          },
        )
        span.end(end_time_unix_nano=wall)
        spans.push(span.snapshot())
        provider.shutdown().unwrap()
      }
    }
    // Selection is opt-in at the CLI. Worker lifetime supplies the hard bound.
    let trace_exporter = @otlp.SpanExporter::builder()
      .with_endpoint(endpoint + "/v1/traces")
      .with_protocol(protocol)
      .with_timeout(timeout)
      .build()
      .unwrap()
    let log_exporter = @otlp.LogExporter::builder()
      .with_endpoint(endpoint + "/v1/logs")
      .with_protocol(protocol)
      .with_timeout(timeout)
      .build()
      .unwrap()
    let metric_exporter = @otlp.MetricExporter::builder()
      .with_endpoint(endpoint + "/v1/metrics")
      .with_protocol(protocol)
      .with_timeout(timeout)
      .build()
      .unwrap()
    trace_exporter.export_batch(spans[:]).unwrap()
    log_exporter.export_batch(logs[:]).unwrap()
    metric_exporter.export_batch(meter_provider.collect()[:]).unwrap()
    meter_provider.shutdown().unwrap()
    trace_exporter.force_flush().unwrap()
    log_exporter.force_flush().unwrap()
    metric_exporter.force_flush().unwrap()
    trace_exporter.shutdown().unwrap()
    log_exporter.shutdown().unwrap()
    metric_exporter.shutdown().unwrap()
  } catch {
    _ => {
      @stdio.stderr.write("observability.native_export_failed\n")
      @sys.exit(1)
    }
  }
}
