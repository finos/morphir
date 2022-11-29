module Morphir.Visual.Components.Card exposing (..)

import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Markdown.Parser as Markdown
import Markdown.Renderer
import Morphir.Visual.Theme as Theme exposing (Theme)


viewAsCard : Theme -> Element msg -> String -> Element.Color -> String -> Element msg -> Element msg
viewAsCard theme header class backgroundColor docs content =
    let
        white =
            rgb 1 1 1

        cont =
            el
                [ alignTop
                , height fill
                , width fill
                ]
                content
    in
    column
        [ padding (theme |> Theme.scaled 3)
        , spacing (theme |> Theme.scaled 3)
        ]
        [ row
            [ width fill
            , paddingXY (theme |> Theme.scaled -2) (theme |> Theme.scaled -6)
            , spacing (theme |> Theme.scaled 2)
            , Font.size (theme |> Theme.scaled 3)
            ]
            [ el [ Font.bold ] header
            , el [ alignLeft, Font.color theme.colors.secondaryInformation ] (text class)
            ]
        , el
            [ Background.color white
            , Border.rounded 3
            , width fill
            , height fill
            ]
            (if docs == "" then
                cont

             else
                column [ height fill, width fill ]
                    [ el
                        [ padding (theme |> Theme.scaled -2)
                        , Border.widthEach { bottom = 3, top = 0, left = 0, right = 0 }
                        , Border.color backgroundColor
                        , height fill
                        , width fill
                        ]
                        (let
                            deadEndsToString deadEnds =
                                deadEnds
                                    |> List.map Markdown.deadEndToString
                                    |> String.join "\n"
                         in
                         case
                            docs
                                |> Markdown.parse
                                |> Result.mapError deadEndsToString
                                |> Result.andThen (\ast -> Markdown.Renderer.render Markdown.Renderer.defaultHtmlRenderer ast)
                         of
                            Ok rendered ->
                                rendered |> List.map html |> paragraph []

                            Err errors ->
                                text errors
                        )
                    , cont
                    ]
            )
        ]
