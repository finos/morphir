// Based on finos/morphir's v4 semantic model and schema.
// Copyright 2026 FINOS. SPDX-License-Identifier: Apache-2.0

///|
#derive(Eq, Debug)
pub(all) struct ModuleSpecification {
  annotations : Array[Annotation]
  types : Map[Name, Documented[TypeSpecification]]
  values : Map[Name, Documented[ValueSpecification]]
  doc : String?
}

///|
#derive(Eq, Debug)
pub(all) struct ModuleDefinition {
  types : Map[Name, AccessControlled[Documented[TypeDefinition]]]
  values : Map[Name, AccessControlled[Documented[ValueDefinition]]]
  doc : String?
}

///|
#derive(Eq, Debug)
pub(all) struct PackageSpecification {
  modules : Map[ModuleName, ModuleSpecification]
}

///|
#derive(Eq, Debug)
pub(all) struct PackageDefinition {
  modules : Map[ModuleName, AccessControlled[ModuleDefinition]]
}

///|
pub type Dependencies = Map[PackageName, PackageSpecification]

///|
/// Application dependencies carry implementations for static linking.
pub type ApplicationDependencies = Map[PackageName, PackageDefinition]

///|
#derive(Eq, Debug)
pub(all) enum EntryPointKind {
  Main
  Command
  Handler
  Job
  Policy
}

///|
#derive(Eq, Debug)
pub(all) struct EntryPoint {
  target : FQName
  kind : EntryPointKind
  doc : String?
}

///|
#derive(Eq, Debug)
pub(all) enum Distribution {
  Library(PackageName, Dependencies, PackageDefinition)
  Specs(PackageName, Dependencies, PackageSpecification)
  Application(
    PackageName,
    ApplicationDependencies,
    PackageDefinition,
    Map[String, EntryPoint]
  )
}

///|
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
  // Resolve the fallible default in the body: MoonBit 0.10.14 native release
  // code generation emits an incompatible result type for a raising default.
  let format_version = match format_version {
    Some(version) => version
    None => @version.FormatVersion::baseline(4U)
  }
  format_version.check_family(4U)
  { format_version, distribution, }
}
