///|
pub(open) trait ToMorphirJson {
  to_json(Self, MorphirJsonOptions) -> Json
}

///|
pub fn[A : ToMorphirJson] to_morphir_json(
  value : A,
  options? : MorphirJsonOptions = Default::default(),
) -> Json {
  value.to_json(options)
}

///|
pub impl ToMorphirJson for Unit with to_json(
  _ : Unit,
  options : MorphirJsonOptions,
) {
  match options.unit_encoding {
    UnitJsonEncoding::AsNull => Json::null()
    UnitJsonEncoding::AsEmptyObject => Json::object({})
  }
}

///|
pub impl ToMorphirJson for Bool with to_json(
  self : Bool,
  _ : MorphirJsonOptions,
) {
  Json::boolean(self)
}

///|
pub impl ToMorphirJson for String with to_json(
  self : String,
  _ : MorphirJsonOptions,
) {
  Json::string(self)
}

///|
pub impl ToMorphirJson for StringView with to_json(
  self : StringView,
  _ : MorphirJsonOptions,
) {
  Json::string(self.to_string())
}

///|
pub impl ToMorphirJson for Json with to_json(
  self : Json,
  _ : MorphirJsonOptions,
) {
  self
}

///|
pub impl[A : ToMorphirJson] ToMorphirJson for @list.List[A] with to_json(
  self : @list.List[A],
  options : MorphirJsonOptions,
) -> Json {
  Json::array(self.map(item => item.to_json(options)).to_array())
}
