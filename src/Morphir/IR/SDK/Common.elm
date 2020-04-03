module Morphir.IR.SDK.Common exposing (..)

import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackagePath)
import Morphir.IR.Path as Path
import Morphir.IR.QName as QName


packageName : PackagePath
packageName =
    Path.fromString "Morphir.SDK"


toFQName : ModulePath -> String -> FQName
toFQName modulePath localName =
    localName
        |> Name.fromString
        |> QName.fromName modulePath
        |> FQName.fromQName packageName
