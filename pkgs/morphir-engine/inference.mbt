///|
/// The dependency specifications for inference: the SDK, then the distribution's own dependencies, which
/// `@typing.infer` adds itself.
fn inference_deps(
  file : @ir.IRFile,
) -> Map[@ir.PackageName, @ir.PackageSpecification] {
  let numeric_source = match file.distribution {
    Library(_, dependencies, _) => {
      let source_package = @ir.Path::parse("morphir/moonbit-source") catch {
        _ => panic()
      }
      match dependencies.get(source_package) {
        Some(spec) =>
          spec.modules.contains(
            @ir.Path::parse("numeric") catch {
              _ => panic()
            },
          )
        None => false
      }
    }
    _ => false
  }
  Map::from_array([
    (
      @sdk_spec.sdk_package_name(),
      if numeric_source {
        @sdk_spec.numeric_sdk_specification() catch {
          _ => panic()
        }
      } else {
        @sdk_spec.sdk_specification()
      },
    ),
  ])
}

///|
/// Runs inference over `unit`. In Check the unit is unchanged. In Fill the filled file replaces the distribution;
/// with `checkpoint`, through `apply_rewrite` with `fill_lineage`, so that metadata stays on its logical nodes,
/// and with `MetadataPolicy::no_derived`, so that a written type gets no metadata of its own.
pub fn infer_unit(
  unit : @data.IRUnit,
  mode : @typing.Mode,
  checkpoint : Bool,
) -> @data.IRUnit raise {
  let filled = @typing.infer(
    unit.distribution,
    inference_deps(unit.distribution),
    mode,
  )
  guard mode is Fill else { return unit }
  if !checkpoint {
    return { ..unit, distribution: filled, }
  }
  @data.apply_rewrite(
    unit,
    { distribution: filled, lineage: Some(@data.fill_lineage(unit, filled)), },
    "inference",
    "inference",
    @data.MetadataPolicy::no_derived(),
  )
}

///|
/// The mode of a `pipeline.inference` value. `None` is `off`.
fn inference_mode(value : String) -> @typing.Mode? raise {
  match value {
    "off" => None
    "fill" => Some(Fill)
    "check" => Some(Check)
    _ =>
      raise @configuration.Invalid(
        "pipeline.inference must be 'off', 'fill' or 'check', not '" +
        value +
        "'",
      )
  }
}
