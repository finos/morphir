// Adapted from Morphir.IR.Module, Package and Distribution in finos/morphir-elm.
// Copyright 2020 Morgan Stanley. Copyright 2026 FINOS.
// SPDX-License-Identifier: Apache-2.0

///|
#derive(Eq, Debug)
pub(all) struct ModuleSpecification[TA] {
  types : Map[Name, Documented[TypeSpecification[TA]]]
  values : Map[Name, Documented[ValueSpecification[TA]]]
  doc : String?
}

///|
#derive(Eq, Debug)
pub(all) struct ModuleDefinition[TA, VA] {
  types : Map[Name, AccessControlled[Documented[TypeDefinition[TA]]]]
  values : Map[Name, AccessControlled[Documented[ValueDefinition[TA, VA]]]]
  doc : String?
}

///|
#derive(Eq, Debug)
pub(all) struct PackageSpecification[TA] {
  modules : Map[ModuleName, ModuleSpecification[TA]]
}

///|
#derive(Eq, Debug)
pub(all) struct PackageDefinition[TA, VA] {
  modules : Map[ModuleName, AccessControlled[ModuleDefinition[TA, VA]]]
}

///|
pub type Dependencies = Map[PackageName, PackageSpecification[Unit]]

///|
#derive(Eq, Debug)
pub(all) enum Distribution {
  Library(PackageName, Dependencies, PackageDefinition[Unit, Type[Unit]])
}

///|
/// An envelope cannot be constructed with a mismatching format family.
#derive(Eq, Debug)
pub struct IRFile {
  format_version : @version.FormatVersion
  distribution : Distribution
}

///|
pub fn IRFile::new(
  distribution : Distribution,
  format_version? : @version.FormatVersion,
) -> IRFile raise @version.VersionError {
  let format_version = match format_version {
    Some(version) => version
    None => @version.FormatVersion::baseline(2U)
  }
  format_version.check_family(2U)
  { format_version, distribution, }
}
