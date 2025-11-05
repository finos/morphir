///|
pub impl @codec.ToMorphirJson for PackageName with to_json(
  self : PackageName,
  options : @codec.MorphirJsonOptions,
) -> Json {
  @codec.ToMorphirJson::to_json(self.0, options)
}
