module Morphir.Visual.ViewLambda exposing (..)

import Element exposing (Element, el, fill, padding, row, text, width)
import Element.Background as Background
import Element.Border as Border
import Morphir.IR.FQName exposing (getLocalName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), TypedValue, Value)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Components.DecisionTable exposing (Match(..))
import Morphir.Visual.Config exposing (Config, HighlightState(..))
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (mediumPadding, smallPadding)
import Morphir.Visual.ViewLiteral as ViewLiteral


view : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> Pattern ( Int, Type () ) -> Value () ( Int, Type () ) -> Element msg
view config viewValue pattern val =
    let
        styles =
            [ Background.color config.state.theme.colors.backgroundColor, smallPadding config.state.theme |> padding, Border.rounded 6 ]
    in
    case pattern of
        Value.WildcardPattern _ ->
            el [ mediumPadding config.state.theme |> padding ] (text "-> _")

        Value.LiteralPattern va literal ->
            row styles [ text " -> ", el [ mediumPadding config.state.theme |> padding ] (ViewLiteral.view config literal) ]

        Value.ConstructorPattern tpe fQName matches ->
            row styles [ text <| nameToText (getLocalName fQName), text " -> ", viewValue config val ]

        Value.AsPattern _ (Value.WildcardPattern _) name ->
            row styles [ el [ mediumPadding config.state.theme |> padding ] (text (nameToText name)), text " -> ", viewValue config val ]

        Value.AsPattern tpe asPattern name ->
            row styles [ el [ mediumPadding config.state.theme |> padding ] (text (nameToText name)), text " -> ", viewValue config val ]

        _ ->
            Element.none


toTypedValue : EnrichedValue -> TypedValue
toTypedValue visualTypedValue =
    visualTypedValue
        |> Value.mapValueAttributes (always ()) (always Tuple.second (Value.valueAttribute visualTypedValue))


toTypedPattern : Pattern ( Int, Type () ) -> Pattern (Type ())
toTypedPattern match =
    match |> Value.mapPatternAttributes (always Tuple.second (Value.patternAttribute match))
