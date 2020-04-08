module Morphir.IR.SDK.Common exposing (..)

import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Package exposing (PackagePath)
import Morphir.IR.Path as Path
import Morphir.IR.QName as QName
import Morphir.IR.Value as Value exposing (Value)


packageName : PackagePath
packageName =
    Path.fromString "Morphir.SDK"


toFQName : ModulePath -> String -> FQName
toFQName modulePath localName =
    localName
        |> Name.fromString
        |> QName.fromName modulePath
        |> FQName.fromQName packageName


binaryApply : ModulePath -> String -> a -> Value a -> Value a -> Value a
binaryApply moduleName localName attributes arg1 arg2 =
    Value.Apply attributes (Value.Apply attributes (Value.Reference attributes (toFQName moduleName localName)) arg1) arg2
