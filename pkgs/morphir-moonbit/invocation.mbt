///|
pub(all) struct InvocationEntry {
  fqname : String
  generated_name : String
  inputs : Array[@execution.ValueType]
  output : @execution.ValueType
  input_codecs : Array[String]
  output_codec : String
}

///|
fn invocation_entry(ctx : Lowering, d : Declaration) -> InvocationEntry? {
  if !d.public {
    return None
  }
  let inputs = []
  for (_, t) in d.inputs {
    if !boundary_supported(ctx, t, Map([])) {
      return None
    }
    guard boundary_type(t) is Some(v) else { return None }
    inputs.push(v)
  }
  if !boundary_supported(ctx, d.output, Map([])) {
    return None
  }
  guard boundary_type(d.output) is Some(output) else { return None }
  Some({
    fqname: d.fqname.to_canonical(),
    generated_name: ctx.names.names[value_node(d.fqname)],
    inputs,
    output,
    input_codecs: d.inputs.map(p => decoder(p.1)),
    output_codec: encoder(d.output),
  })
}

///|
/// A separate consumer package. Only entry selection affects its source.
pub fn invocation_driver(
  output : Output,
  entries : Array[String],
) -> Array[Artifact] raise GenerationError {
  let names = entries.copy()
  names.sort()
  let cases = []
  let seen = Map([])
  for name in names {
    if seen.contains(name) {
      continue
    }
    seen[name] = true
    guard output.invocations.filter(e => e.fqname == name).get(0) is Some(entry) else {
      raise Invalid(
        "moonbit.unsupported_entry", name, "A public entry with supported boundary types is required",
      )
    }
    let arguments = []
    for i = 0; i < entry.inputs.length(); i = i + 1 {
      arguments.push(
        entry.input_codecs[i] + "(call.arguments[" + i.to_string() + "])",
      )
    }
    let mut call = "@model." + entry.generated_name + "()"
    for argument in arguments {
      call = "{ let function = " + call + "; function(" + argument + ") }"
    }
    let wrapped = entry.output_codec + "(" + call + ")"
    cases.push(
      quote(name) +
      " => { if call.arguments.length() != " +
      entry.inputs.length().to_string() +
      " { raise @execution.Invalid(\"execution.wrong_arity\") }; " +
      wrapped +
      " }",
    )
  }
  let source = output.invocation_codecs +
    (
      #|///|
      #|fn record_field(items : Array[(String, @execution.Value)], name : String) -> @execution.Value raise {
      #|  let fields = items.filter(p => p.0 == name)
      #|  if fields.length() != 1 { raise @execution.Invalid("execution.record_field") }
      #|  fields[0].1
      #|}
      #|///|
      #|fn invoke_value(call : @execution.Call) -> @execution.Value raise {
      #|  match call.entry {
      #|
    )
  let ending =
    #|    _ => raise @execution.Invalid("execution.unknown_entry")
    #|  }
    #|}
    #|///|
    #|pub fn invoke(call : @execution.Call) -> @execution.Value raise {
    #|  invoke_value(call) catch {
    #|    @sdk.DivisionByZero => @execution.ModelError("sdk.division_by_zero")
    #|    @sdk.InvalidNumber(_) => @execution.ModelError("sdk.invalid_number")
    #|    @sdk.OutOfRange(_) => @execution.ModelError("sdk.out_of_range")
    #|    @sdk.InvalidComparison(_) => @execution.ModelError("sdk.invalid_comparison")
    #|    @sdk.UnrepresentableText(_) => @execution.ModelError("sdk.unrepresentable_text")
    #|    error => raise error
    #|  }
    #|}
    #|
  [
    {
      path: "moon.mod",
      role: ModuleManifest,
      content: Text(
        "name = \"morphir-generated/driver\"\nversion = \"0.0.0\"\nimport {\n" +
        quote(output.project.module_name + "@0.0.0") +
        ",\n\"finos/morphir-sdk@0.1.0\",\n\"finos/morphir-execution@0.1.0\",\n\"moonrockz/ion@0.5.0\",\n\"moonbitlang/x@0.5.5\",\n}\n",
      ),
    },
    {
      path: "moon.pkg",
      role: PackageManifest,
      content: Text(
        "import {\n" +
        quote(output.project.module_name) +
        " @model,\n\"finos/morphir-sdk\" @sdk,\n\"finos/morphir-sdk/integer\",\n\"finos/morphir-sdk/decimal\",\n\"finos/morphir-sdk/list\",\n\"finos/morphir-execution\" @execution,\n\"moonbitlang/core/bigint\",\n}\nwarnings = \"-16-29\"\n",
      ),
    },
    {
      path: "driver.mbt",
      role: Source,
      content: Text(source + cases.join("\n") + "\n" + ending),
    },
  ]
}
