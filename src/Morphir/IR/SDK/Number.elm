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


numberClass : extra -> Type extra
numberClass extra =
    Variable [ "number" ] extra


negate : extra -> extra -> Value extra -> Value extra
negate refExtra valueExtra arg =
    Value.Apply (Value.Reference (fromLocalName "negate") refExtra) arg valueExtra
