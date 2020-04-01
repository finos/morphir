module Morphir.IR.SDK.Number exposing (..)

import Dict
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Common exposing (packageName)
import Morphir.IR.Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)


moduleName : Path
moduleName =
    [ [ "number" ] ]


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.empty
    , values =
        Dict.empty
    }


fromLocalName : String -> FQName
fromLocalName name =
    name
        |> Name.fromString
        |> QName.fromName moduleName
        |> FQName.fromQName packageName


numberClass : a -> Type a
numberClass attributes =
    Variable attributes [ "number" ]


negate : a -> a -> Value a -> Value a
negate refAttributes valueAttributes arg =
    Value.Apply valueAttributes (Value.Reference refAttributes (fromLocalName "negate")) arg
