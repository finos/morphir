///|
pub impl @codec.ToMorphirJson for ModulePath with to_json(
  self : ModulePath,
  options : @codec.MorphirJsonOptions,
) -> Json {
  @codec.ToMorphirJson::to_json(self.0, options)
}
