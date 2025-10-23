///|
pub impl[A : @codec.ToMorphirJson] @codec.ToMorphirJson for Type[A] with to_json(
  self : Type[A],
  options : @codec.MorphirJsonOptions,
) -> Json {
  match self {
    Variable(attributes, name) =>
      Json::array([
        Json::string("Variable"),
        attributes.to_json(options),
        name.to_json(options),
      ])
    Tuple(attributes, element_types) =>
      Json::array([
        Json::string("Tuple"),
        attributes.to_json(options),
        ToMorphirJson::to_json(element_types, options),
      ])
    Function(attributes, parameter_type, return_type) =>
      Json::array([
        Json::string("Function"),
        attributes.to_json(options),
        parameter_type.to_json(options),
        return_type.to_json(options),
      ])
    Unit(attributes) =>
      Json::array([Json::string("Unit"), attributes.to_json(options)])
  }
}
