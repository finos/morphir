module Morphir.Visual.ViewReference exposing (..)

import Element exposing (Element, padding, spacing, text)
import Element.Events exposing (onClick)
import Morphir.IR.FQName exposing (FQName)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding, smallSpacing)


view : Config msg -> (EnrichedValue -> Element msg) -> FQName -> Element msg
view config viewValue (( packageName, moduleName, localName ) as fQName) =
    Element.row
        [ smallPadding config.state.theme |> padding
        , smallSpacing config.state.theme |> spacing
        , onClick (config.handlers.onReferenceClicked fQName False)
        ]
        [ Element.el []
            (text
                (nameToText localName)
            )
        ]
