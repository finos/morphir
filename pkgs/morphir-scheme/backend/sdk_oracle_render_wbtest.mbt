///|
/// Render runtime values in Elm Debug.toString form for the pinned corpus.
/// Dict, Set, Decimal and fixed-width results use the documented projection
/// in run_elm_oracle.py, so opaque internals do not become fixture contracts.
fn oracle_render(
  value : @scheme.Value,
  depth : Int32,
) -> String raise @scheme.SchemeError {
  if depth > 256 {
    raise @scheme.Limit("Elm oracle rendering depth")
  }
  match value {
    @scheme.Number(@scheme.Number::Integer(_)) => @scheme.value_to_string(value)
    @scheme.Number(@scheme.Number::Real(n)) =>
      if @basics.is_nan(n) {
        "NaN"
      } else if @basics.is_infinite(n) {
        if n < 0.0 {
          "-Infinity"
        } else {
          "Infinity"
        }
      } else {
        let source = @scheme.value_to_string(value)
        if source.has_suffix(".0") {
          source.clamped_view(end=source.length() - 2).to_owned()
        } else {
          source
        }
      }
    @scheme.Boolean(b) => if b { "True" } else { "False" }
    @scheme.Text(_) => @scheme.value_to_string(value)
    @scheme.Character(c) => "'" + c.to_string() + "'"
    @scheme.Tagged("sdk-character", _) => {
      let text = sdk_character(value).to_string() catch {
        _ => raise @scheme.Invalid("Unrepresentable oracle character")
      }
      "'" + text + "'"
    }
    @scheme.Nil | @scheme.Pair(_, _) =>
      "[" +
      value.to_array().map(item => oracle_render(item, depth + 1)).join(",") +
      "]"
    @scheme.Vector(items) =>
      "(" + items.map(item => oracle_render(item, depth + 1)).join(",") + ")"
    @scheme.Tagged("sdk-dict", [items]) | @scheme.Tagged("sdk-set", [items]) =>
      oracle_render(items, depth + 1)
    @scheme.Tagged("decimal", [source]) => oracle_render(source, depth + 1)
    @scheme.Tagged("morphir/SDK:int#int8", [item])
    | @scheme.Tagged("morphir/SDK:int#int16", [item])
    | @scheme.Tagged("morphir/SDK:int#int32", [item])
    | @scheme.Tagged("morphir/SDK:int#int64", [item]) =>
      oracle_render(item, depth + 1)
    @scheme.Tagged("morphir/SDK:maybe#nothing", []) => "Nothing"
    @scheme.Tagged("morphir/SDK:maybe#just", [item]) =>
      "Just " + oracle_render(item, depth + 1)
    @scheme.Tagged("morphir/SDK:result#ok", [item]) =>
      "Ok " + oracle_render(item, depth + 1)
    @scheme.Tagged("morphir/SDK:result#err", [item]) =>
      "Err " + oracle_render(item, depth + 1)
    @scheme.Tagged("morphir/SDK:basics#l-t", []) => "LT"
    @scheme.Tagged("morphir/SDK:basics#e-q", []) => "EQ"
    @scheme.Tagged("morphir/SDK:basics#g-t", []) => "GT"
    _ => raise @scheme.Invalid("Unsupported Elm oracle result shape")
  }
}
