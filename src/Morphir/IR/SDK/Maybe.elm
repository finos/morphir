module Morphir.IR.SDK.Maybe exposing (..)

import Morphir.IR.Advanced.Type exposing (Type(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Common exposing (packageName)


moduleName : Path
moduleName =
    [ [ "maybe" ] ]


fromLocalName : String -> FQName
fromLocalName name =
    name
        |> Name.fromString
        |> QName.fromName moduleName
        |> FQName.fromQName packageName


maybeType : Type extra -> extra -> Type extra
maybeType itemType extra =
    Reference (fromLocalName "maybe") [ itemType ] extra
