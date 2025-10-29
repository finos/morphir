///|
pub impl @codec.ToMorphirJson for FQName with to_json(
  self : FQName,
  options : @codec.MorphirJsonOptions,
) -> Json {
  Json::array([
    @codec.ToMorphirJson::to_json(self.package_name, options),
    @codec.ToMorphirJson::to_json(self.module_path, options),
    @codec.ToMorphirJson::to_json(self.local_name, options),
  ])
}
