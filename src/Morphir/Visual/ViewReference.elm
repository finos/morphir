module Morphir.Visual.ViewReference exposing (..)

import Element exposing (Element, padding, spacing, text)
import Element.Events exposing (onClick)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Context exposing (Context)


view : Context msg -> (Value ta (Type ta) -> Element msg) -> FQName -> Element msg
view context viewValue (( packageName, moduleName, localName ) as fQName) =
    Element.row [ padding 8, spacing 8, onClick (context.onReferenceClicked fQName False) ]
        [ Element.el []
            (text
                (nameToText localName)
            )
        ]
