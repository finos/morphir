module Morphir.IR.SDK.Int exposing (..)

import Morphir.IR.Advanced.Type exposing (Type(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Package exposing (packageName)


moduleName : Path
moduleName =
    [ [ "int" ] ]


fromLocalName : String -> FQName
fromLocalName name =
    name
        |> Name.fromString
        |> QName.fromName moduleName
        |> FQName.fromQName packageName


intType : extra -> Type extra
intType extra =
    Reference (fromLocalName "int") [] extra
