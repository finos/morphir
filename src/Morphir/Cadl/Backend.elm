module Morphir.Cadl.Backend exposing (..)

import Dict exposing (Dict)
import Morphir.Cadl.AST exposing (Name, Namespace, Type(..), TypeDefinition(..))
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Module as Module
import Morphir.IR.Name as IRName exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as IRType exposing (Type(..))
import Morphir.SDK.ResultList as ResultList


type Errors
    = UnsupportedType String


mapDistribution : Distribution -> Result Errors FileMap
mapDistribution distro =
    case distro of
        Library packageName _ packageDef ->
            mapPackageDefinition packageDef
                |> Result.map (prettyPrint packageName)
                |> Result.map (Dict.singleton ( [], Path.toString IRName.toTitleCase "." packageName ))


prettyPrint : PackageName -> Dict String Namespace -> String
prettyPrint packageName namespaces =
    Debug.todo ""


mapPackageDefinition : Package.Definition ta (IRType.Type ()) -> Result Errors (Dict String Namespace)
mapPackageDefinition packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( moduleName, accessControlledModDef ) ->
                accessControlledModDef.value
                    |> mapModuleDefinition
                    |> Result.map
                        (Tuple.pair
                            (Path.toString IRName.toTitleCase "." moduleName)
                        )
            )
        |> ResultList.keepFirstError
        |> Result.map Dict.fromList


mapModuleDefinition : Module.Definition ta (IRType.Type ()) -> Result Errors Namespace
mapModuleDefinition definition =
    definition.types
        |> Dict.toList
        |> List.map
            (\( tpeName, accessControlledDoc ) ->
                accessControlledDoc.value.value
                    |> mapTypeDefinition tpeName
            )
        |> ResultList.keepFirstError
        |> Result.map Dict.fromList


mapTypeDefinition : IRName.Name -> IRType.Definition ta -> Result Errors ( Name, TypeDefinition )
mapTypeDefinition tpeName definition =
    case definition of
        IRType.TypeAliasDefinition _ tpe ->
            tpe
                |> mapType
                |> Result.map
                    (\cadlType ->
                        Alias (iRNameToName tpeName) cadlType
                            |> Tuple.pair (iRNameToName tpeName)
                    )

        IRType.CustomTypeDefinition lists accessControlled ->
            Err (UnsupportedType "Custom Type not Supported")


iRNameToName : IRName.Name -> Name
iRNameToName name =
    IRName.toTitleCase name


mapType : IRType.Type ta -> Result Errors Type
mapType tpe =
    case tpe of
        Reference _ fQName types ->
            case FQName.toString fQName of
                "Morphir.SDK:Basics:bool" ->
                    Ok Boolean

                _ ->
                    Err (UnsupportedType (FQName.toString fQName))

        _ ->
            Err (UnsupportedType "Other Types Not Supported")
