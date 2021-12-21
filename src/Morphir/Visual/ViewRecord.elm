module Morphir.Visual.ViewRecord exposing (..)

import Element exposing (Element, centerX, centerY, el, fill, height, padding, text, width)
import Element.Border as Border
import Element.Font as Font
import Morphir.IR.Name as Name exposing (Name)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding)


view : Config msg -> (EnrichedValue -> Element msg) -> List ( Name, EnrichedValue ) -> Element msg
view config viewValue items =
    Element.table
        [ centerX, centerY ]
        { data = items
        , columns =
            [ { header =
                    el [ Border.widthEach { bottom = 1, top = 1, right = 0, left = 1 }, smallPadding config.state.theme |> padding ]
                        (el [ centerX, centerY, Font.bold ] (Element.text "Field Name"))
              , width = fill
              , view =
                    \( name, _ ) ->
                        el [ smallPadding config.state.theme |> padding, width fill, height fill, Border.widthEach { bottom = 1, top = 0, right = 0, left = 1 } ] (el [ centerX, centerY ] (text (nameToText name)))
              }
            , { header =
                    el [ Border.widthEach { bottom = 1, top = 1, right = 1, left = 1 }, smallPadding config.state.theme |> padding ]
                        (el [ centerX, centerY, Font.bold ] (Element.text "Field Value"))
              , width = fill
              , view =
                    \( _, val ) ->
                        el [ smallPadding config.state.theme |> padding, width fill, height fill, Border.widthEach { bottom = 1, top = 0, right = 1, left = 1 } ] (el [ centerX, centerY ] (viewValue val))
              }
            ]
        }
