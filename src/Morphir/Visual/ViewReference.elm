module Morphir.Visual.ViewReference exposing (..)

import Element exposing (Element, text)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)


view : (Value ta (Type ta) -> Element msg) -> FQName -> Element msg
view viewValue (FQName packageName moduleName localName) =
    text
        (nameToText localName)
