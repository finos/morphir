module Morphir.Visual.Components.TreeViewComponent exposing (..)

import Array exposing (Array)
import Dict exposing (Dict)
import Element exposing (Color, Element, column, el, fill, height, mouseOver, none, padding, paddingEach, pointer, px, rgb, row, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font exposing (center)
import Morphir.Visual.Theme exposing (Theme)
import Set exposing (Set)


type alias NodePath comparable =
    List comparable


type Node comparable msg
    = Node (NodePath comparable -> Element msg) (Array (Element msg)) (Dict comparable (Node comparable msg))


type alias Config comparable msg =
    { onCollapse : NodePath comparable -> msg
    , onExpand : NodePath comparable -> msg
    , collapsedPaths : Set (NodePath comparable)
    , selectedPaths : Set (NodePath comparable)
    }


view : Theme -> Config comparable msg -> Node comparable msg -> Element msg
view theme config node =
    column [ width fill, height fill ] (viewSubTree theme config [] node)


viewSubTree : Theme -> Config comparable msg -> NodePath comparable -> Node comparable msg -> List (Element msg)
viewSubTree theme config nodePath (Node label _ children) =
    let
        depth : Int
        depth =
            List.length nodePath

        indentRight : Int -> Element.Attribute msg
        indentRight by =
            paddingEach
                { left = by * 20
                , right = 0
                , top = 0
                , bottom = 0
                }

        handle : String -> Maybe (NodePath comparable -> msg) -> Element msg
        handle icon maybeOnClick =
            let
                style =
                    [ width (px 20)
                    ]

                attribs =
                    case maybeOnClick of
                        Just handleOnClick ->
                            [ onClick (handleOnClick nodePath)
                            , pointer
                            ]
                                ++ style

                        Nothing ->
                            style
            in
            el
                attribs
                (el
                    [ center, Font.size 12, Font.color (rgb 0.3 0.3 0.3) ]
                    (text icon)
                )

        viewNode : Element msg -> Element msg
        viewNode collapseControl =
            let
                configurableStyles =
                    if config.selectedPaths |> Set.member nodePath then
                        [ Font.bold
                        , Background.color theme.colors.brandPrimaryLight
                        , Border.widthEach { left = 2, right = 0, bottom = 0, top = 0 }
                        , Border.color theme.colors.primaryHighlight
                        ]

                    else
                        []
            in
            el
                (List.concat
                    [ configurableStyles
                    , [ width fill
                      , padding 2
                      , Element.focused [ Background.color theme.colors.gray ]
                      , mouseOver
                            [ Background.color theme.colors.gray
                            , Border.color theme.colors.primaryHighlight
                            ]
                      ]
                    ]
                )
                (row [ indentRight depth ]
                    [ collapseControl
                    , label nodePath
                    ]
                )
    in
    if Dict.isEmpty children then
        [ viewNode (handle "" Nothing)
        ]

    else if config.collapsedPaths |> Set.member nodePath then
        [ viewNode (handle theme.icons.closed (Just config.onExpand))
        ]

    else
        List.concat
            [ [ viewNode (handle theme.icons.opened (Just config.onCollapse))
              ]
            , children
                |> Dict.toList
                |> List.map
                    (\( key, childNode ) ->
                        viewSubTree theme config (key :: nodePath) childNode
                    )
                |> List.concat
            ]
