///|
pub fn value_tree(value : Json) -> Json {
  value_node(value, 0, Ref(500))
}

///|
fn node_text(value : Json, name : String) -> String {
  match field(value, name) {
    String(s) => s
    _ => ""
  }
}

///|
/// Presentation is bounded independently of the lossless canonical result.
fn value_node(value : Json, depth : Int, budget : Ref[Int]) -> Json {
  fn omitted() -> Json {
    { "kind": "truncated", "text": "Result display limit reached" }
  }
  if budget.val <= 0 {
    return omitted()
  }
  budget.val -= 1
  if depth > 32 {
    return omitted()
  }
  let kind = node_text(value, "type")
  fn children(values : Array[Json]) -> Array[Json] {
    let result = []
    for child in values {
      if budget.val <= 0 {
        result.push(omitted())
        break
      }
      result.push(value_node(child, depth + 1, budget))
    }
    result
  }
  match kind {
    "list" | "tuple" =>
      {
        "kind": kind,
        "items": children(
          @wire.array(@wire.field(value, "items")) catch {
            _ => []
          },
        ),
      }
    "record" => {
      let fields : Array[Json] = []
      let entries = @wire.array(@wire.field(value, "fields")) catch { _ => [] }
      for field in entries {
        if budget.val <= 0 {
          fields.push({ "name": "…", "value": omitted() })
          break
        }
        fields.push({
          "name": node_text(field, "name"),
          "value": value_node(
            @wire.field(field, "value") catch {
              _ => Json::null()
            },
            depth + 1,
            budget,
          ),
        })
      }
      { "kind": "record", "fields": fields }
    }
    "custom" =>
      {
        "kind": "constructor",
        "tag": node_text(value, "owner") + " / " + node_text(value, "tag"),
        "items": children(
          @wire.array(@wire.field(value, "items")) catch {
            _ => []
          },
        ),
      }
    "maybe" | "result" => {
      let values = match (@wire.optional(value, "value") catch { _ => None }) {
        Some(v) => [v]
        None => []
      }
      {
        "kind": "constructor",
        "tag": kind + " / " + node_text(value, "case"),
        "items": children(values),
      }
    }
    _ => {
      let text = if kind == "int" {
        node_text(value, "value")
      } else {
        value.stringify()
      }
      if text.length() > 16384 {
        omitted()
      } else {
        { "kind": kind, "text": text }
      }
    }
  }
}
