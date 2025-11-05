///|
pub impl[TA, VA : ToMorphirJson] ToMorphirJson for Value[TA, VA] with to_json(
  self : Value[TA, VA],
  options : MorphirJsonOptions,
) -> Json {
  match self {
    Field(attributes, value, name) =>
      Json::array([
        Json::string("field"),
        attributes.to_json(options),
        value.to_json(options),
        name.to_json(options),
      ])
    Unit(attributes) =>
      Json::array([Json::string("unit"), attributes.to_json(options)])
  }
}
