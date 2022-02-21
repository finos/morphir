module Morphir.Elm.ModuleName exposing (..)

import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackageName)


type alias ModuleName =
    List String


toIRModuleName : PackageName -> ModuleName -> Module.ModuleName
toIRModuleName packageName elmModuleName =
    elmModuleName
        |> List.drop (packageName |> List.length)
        |> List.map Name.fromString
