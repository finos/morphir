module Morphir.Visual.ViewRecord exposing (..)

import Element exposing (Element, el, padding, rgb, none)
import Element.Background as Background
import Element.Border as Border
import Morphir.IR.Name exposing (Name)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding)


view : Config msg -> (EnrichedValue -> Element msg) -> List ( Name, EnrichedValue ) -> Element msg
view config viewValue items =
    let
        fields =
            List.map (\( name, val ) -> ( name, viewValue val )) items
    in

    if List.isEmpty items then
        none
    else
        el
            [ smallPadding config.state.theme |> padding
            , Background.color (rgb 0.7 0.8 0.9)
            , Border.rounded 7
            ]
            (FieldList.view fields)
