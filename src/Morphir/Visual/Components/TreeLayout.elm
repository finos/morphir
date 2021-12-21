module Morphir.Visual.Components.TreeLayout exposing (..)

import Array exposing (Array)
import Element exposing (Color, Element, column, el, fill, height, none, padding, paddingEach, pointer, px, rgb, row, text, width)
import Element.Background as Background
import Element.Events exposing (onClick)
import Element.Font as Font exposing (center)
import Set exposing (Set)


type alias NodePath =
    List Int


type Node msg
    = Node (NodePath -> Element msg) (Array (Element msg)) (List (Node msg))


type alias Theme =
    { colors :
        { selectedRowBackground : Maybe Color
        }
    , icons :
        { collapsibleBranch : Element Never
        , expandableBranch : Element Never
        }
    }


defaultTheme : Theme
defaultTheme =
    { colors =
        { selectedRowBackground = Just (rgb 0.8 0.9 0.9)
        }
    , icons =
        { collapsibleBranch = text "⮞"
        , expandableBranch = text "⮟"
        }
    }


type alias Config msg =
    { onCollapse : NodePath -> msg
    , onExpand : NodePath -> msg
    , collapsedPaths : Set NodePath
    , selectedPaths : Set NodePath
    }


view : Theme -> Config msg -> Node msg -> Element msg
view theme config node =
    column [ width fill, height fill ] (viewSubTree theme config [] node)


viewSubTree : Theme -> Config msg -> NodePath -> Node msg -> List (Element msg)
viewSubTree theme config nodePath (Node label attributes children) =
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

        handle : Element msg -> Maybe (NodePath -> msg) -> Element msg
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
                    icon
                )

        viewNode : Element msg -> Element msg
        viewNode collapseControl =
            let
                configurableStyles =
                    List.filterMap identity
                        [ if config.selectedPaths |> Set.member nodePath then
                            Maybe.map Background.color theme.colors.selectedRowBackground

                          else
                            Nothing
                        ]
            in
            el
                (List.concat
                    [ configurableStyles
                    , [ width fill
                      , padding 2
                      ]
                    ]
                )
                (row [ indentRight depth ]
                    [ collapseControl
                    , label nodePath
                    ]
                )
    in
    if List.isEmpty children then
        [ viewNode (handle none Nothing)
        ]

    else if config.collapsedPaths |> Set.member nodePath then
        [ viewNode (handle (Element.map never theme.icons.expandableBranch) (Just config.onExpand))
        ]

    else
        List.concat
            [ [ viewNode (handle (Element.map never theme.icons.collapsibleBranch) (Just config.onCollapse))
              ]
            , children
                |> List.indexedMap
                    (\index childNode ->
                        viewSubTree theme config (index :: nodePath) childNode
                    )
                |> List.concat
            ]
