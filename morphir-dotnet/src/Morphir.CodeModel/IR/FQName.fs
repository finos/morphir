module Morphir.IR.FQName

open Morphir.IR.Path
open Morphir.IR.Name
open Morphir.IR.QName

/// <summary>
/// Tyoe that represents a fully-qualified name. The parameters are: packagePath, modulePath, localName.
/// </summary>
type FQName = FQName of packagePath: Path * modulePath: Path * localName: Name

/// <summary>
/// Create a fully-qualified name.
/// </summary>
let inline fQName packagePath modulePath localName =
    FQName(packagePath, modulePath, localName)

let fromQName packagePath qName =
    let (QName(modulePath, localName)) = qName
    FQName(packagePath, modulePath, localName)

let getPackagePath =
    function
    | FQName(packagePath, _, _) -> packagePath

let getModulePath =
    function
    | FQName(_, modulePath, _) -> modulePath

/// <summary>
/// Get the local name part of a fully-qualified name.
/// </summary>
let getLocalName =
    function
    | FQName(_, _, localName) -> localName

let inline fqn (packageName: string) (moduleName: string) (localName: string) =
    fQName (Path.fromString packageName) (Path.fromString moduleName) (Name.fromString localName)

let toReferenceName (FQName(packageName, moduleName, localName)) =
    let packageNameString = Path.toString Name.toTitleCase "." packageName
    let moduleNameString = Path.toString Name.toTitleCase "." moduleName
    let localNameString = Name.toTitleCase localName
    $"{packageNameString}.{moduleNameString}.{localNameString}"

/// <summary>
/// Convert a fully-qualified name to a string.
/// </summary>
let toString =
    function
    | FQName(packagePath, modulePath, localName) ->
        sprintf
            "%s:%s:%s"
            (packagePath
             |> Path.toString Name.toTitleCase ".")
            (modulePath
             |> Path.toString Name.toTitleCase ".")
            (Name.toCamelCase localName)
