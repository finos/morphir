module Morphir.IR.SDK.String exposing (..)

import Morphir.IR.Advanced.Type exposing (Type(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Common exposing (packageName)


moduleName : Path
moduleName =
    [ [ "string" ] ]


fromLocalName : String -> FQName
fromLocalName name =
    name
        |> Name.fromString
        |> QName.fromName moduleName
        |> FQName.fromQName packageName


stringType : extra -> Type extra
stringType extra =
    Reference (fromLocalName "string") [] extra
