module Morphir.Visual.ViewDestructure exposing (..)

import Element exposing (Element, el, padding, text)
import Element.Background as Background
import Element.Border as Border
import Morphir.IR.FQName exposing (getLocalName)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Config exposing (Config, HighlightState(..))
import Morphir.Visual.EnrichedValue exposing (EnrichedValue)
import Morphir.Visual.Theme exposing (mediumPadding, smallPadding)
import Morphir.Visual.ViewLiteral as ViewLiteral
view : Config msg -> (Config msg -> EnrichedValue -> Element msg) -> Pattern ( Int, Type () ) -> Value () ( Int, Type () ) -> Value () ( Int, Type () ) -> Element msg
view config viewValue pattern val1 val2 = 
        let
          styles =
              [ Background.color config.state.theme.colors.backgroundColor, smallPadding config.state.theme |> padding, Border.rounded 6 ]

          displayPattern p =
              case p of
                  Value.WildcardPattern _ ->
                      [el [ mediumPadding config.state.theme |> padding ] (text "_")]

                  Value.LiteralPattern _ literal ->
                      [ el [ mediumPadding config.state.theme |> padding ] (ViewLiteral.view config literal) ]

                  Value.ConstructorPattern _ fQName _ ->
                      [ text <| nameToText (getLocalName fQName) ]

                  Value.AsPattern _ (Value.WildcardPattern _) name ->
                      [ el [ mediumPadding config.state.theme |> padding ] (text (nameToText name)) ]

                  Value.AsPattern _ asPattern name ->
                      [ el [ mediumPadding config.state.theme |> padding ] (text (nameToText name)), text " as "] ++ displayPattern asPattern

                  Value.TuplePattern _ patternList ->
                      List.concatMap displayPattern patternList

                  Value.HeadTailPattern _ head tail ->
                      displayPattern head ++ displayPattern tail

                  _ ->
                     [ Element.none]
        in
    Element.row styles <| text "("  ::  displayPattern pattern ++ [ text ") = ", viewValue config val1, viewValue config val2 ]