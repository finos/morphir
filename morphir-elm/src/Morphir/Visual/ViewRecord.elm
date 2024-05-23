module Morphir.Visual.ViewRecord exposing (..)

import Dict exposing (Dict)
import Element exposing (Element, el, none, padding)
import Element.Background as Background
import Morphir.IR.Name exposing (Name)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (smallPadding, borderRounded)


view : Config msg -> (EnrichedValue -> Element msg) -> Dict Name EnrichedValue -> Element msg
view config viewValue items =
    let
        fields =
            Dict.toList <| Dict.map (\name val -> viewValue val) items
    in
    if Dict.isEmpty items then
        none

    else
        el
            [ smallPadding config.state.theme |> padding
            , Background.color config.state.theme.colors.brandPrimaryLight
            , borderRounded config.state.theme
            ]
            (FieldList.view config.state.theme fields)
