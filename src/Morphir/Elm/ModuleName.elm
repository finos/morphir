module Morphir.Elm.ModuleName exposing (..)

import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackageName)
import Morphir.IR.Path as Path


type alias ModuleName =
    List String


toIRModuleName : PackageName -> ModuleName -> Maybe Module.ModuleName
toIRModuleName packageName elmModuleName =
    let
        moduleName =
            elmModuleName
                |> List.map Name.fromString
    in
    if packageName |> Path.isPrefixOf moduleName then
        moduleName
            |> List.drop (packageName |> List.length)
            |> Just

    else
        Nothing


fromIRModuleName : Module.ModuleName -> ModuleName
fromIRModuleName irModuleName =
    irModuleName
        |> List.map Name.toTitleCase


toString : ModuleName -> String
toString moduleName =
    moduleName
        |> String.join "."
