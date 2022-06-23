module Morphir.Visual.ViewLambda exposing (..)

import Element exposing (Element, el, padding, row, text)
import Element.Background as Background
import Element.Border as Border
import Morphir.IR.FQName exposing (getLocalName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value)
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

        viewHelper p =
            case p of
                Value.WildcardPattern _ ->
                    [ el [ mediumPadding config.state.theme |> padding ] (text "-> _") ]

                Value.LiteralPattern _ literal ->
                    [ text " -> ", el [ mediumPadding config.state.theme |> padding ] (ViewLiteral.view config literal) ]

                Value.ConstructorPattern _ fQName _ ->
                    [ text <| nameToText (getLocalName fQName), text " -> ", viewValue config val ]

                Value.AsPattern _ (Value.WildcardPattern _) name ->
                    [ el [ mediumPadding config.state.theme |> padding ] (text (nameToText name)), text " -> ", viewValue config val ]

                Value.AsPattern _ asPattern name ->
                    [ el [ mediumPadding config.state.theme |> padding ] (text (nameToText name)), text " as " ] ++ viewHelper asPattern ++ [ text " -> ", viewValue config val ]

                Value.TuplePattern _ patternList ->
                    List.concatMap viewHelper patternList ++ [ text " -> ", viewValue config val ]

                Value.HeadTailPattern _ head tail ->
                    viewHelper head ++ viewHelper tail ++ [ text " -> ", viewValue config val ]

                _ ->
                    [ Element.none ]
    in
    row styles (viewHelper pattern)
