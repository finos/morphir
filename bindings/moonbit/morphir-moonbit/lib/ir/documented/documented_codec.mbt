pub impl[T: @codec.ToMorphirJson] @codec.ToMorphirJson for Documented[T] with to_json(
    self: Documented[T],
    options: @codec.MorphirJsonOptions,
) -> Json {
    Json::object({
        "doc": Json::string(self.doc),
        "value": self.value.to_json(options),
    })
}

pub impl[T: @codec.FromMorphirJson] @codec.FromMorphirJson for Documented[T] with from_json(
    json: Json,
    json_path: @json.JsonPath,
    options: @codec.MorphirJsonOptions,
) -> Documented[T] {
  guard json is Json::Object(obj) else {
    @codec.decode_error(
      json_path,
      "Documented::from_json: expected object with 'doc' and 'value' fields",
    )
  }
  match obj {
    { "doc": Json::String(doc), "value": valueJson, .. } => {
      let value =
        @codec.FromMorphirJson::from_json(valueJson, json_path.add_key("value"), options);
      Documented::new(doc, value)
    }
    _ => {
      @codec.decode_error(
        json_path,
        "Documented::from_json: expected object with 'doc' and 'value' fields",
      )
    }
  }
}