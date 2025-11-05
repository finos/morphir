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
    Reference(attributes, fq_name, type_args) =>
      Json::array([
        Json::string("Reference"),
        attributes.to_json(options),
        fq_name.to_json(options),
        ToMorphirJson::to_json(type_args, options),
      ])
    Tuple(attributes, element_types) =>
      Json::array([
        Json::string("Tuple"),
        attributes.to_json(options),
        ToMorphirJson::to_json(element_types, options),
      ])
    Record(attributes, fields) =>
      Json::array([
        Json::string("Record"),
        attributes.to_json(options),
        ToMorphirJson::to_json(fields, options),
      ])
    ExtensibleRecord(attributes, name, fields) =>
      Json::array([
        Json::string("ExtensibleRecord"),
        attributes.to_json(options),
        name.to_json(options),
        ToMorphirJson::to_json(fields, options),
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

///|
pub impl[A : @codec.ToMorphirJson] @codec.ToMorphirJson for Field[A] with to_json(
  self : Field[A],
  options : @codec.MorphirJsonOptions,
) -> Json {
  Json::object({
    "name": self.name.to_json(options),
    "tpe": self.tpe.to_json(options),
  })
}
