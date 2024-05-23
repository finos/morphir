module Morphir.Visual.Components.InputComponent exposing (checkBox, multiLine, searchInput, textInput)

import Element exposing (Element, below, el, moveDown, padding, paddingXY, rgb, rgba, text)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input
import Morphir.Visual.Theme as Theme exposing (Theme)


type alias TextInputConfig msg =
    { onChange : String -> msg
    , text : String
    , placeholder : Maybe (Element.Input.Placeholder msg)
    , label : Element.Input.Label msg
    }


type alias MultilineTextInputConfig msg =
    { onChange : String -> msg
    , text : String
    , placeholder : Maybe (Element.Input.Placeholder msg)
    , label : Element.Input.Label msg
    , spellcheck : Bool
    }


type alias CheckboxConfig msg =
    { onChange : Bool -> msg
    , checked : Bool
    , label : Element.Input.Label msg
    }


defaultStyles : Theme -> List (Element.Attribute msg)
defaultStyles theme =
    [ Element.focused
        [ Border.color theme.colors.primaryHighlight
        , Border.shadow
            { offset = ( 0, 0 )
            , size = 0
            , blur = 3
            , color = theme.colors.primaryHighlight
            }
        ]
    , paddingXY (theme |> Theme.mediumPadding) (theme |> Theme.smallPadding)
    , Font.size theme.fontSize
    , Theme.borderRounded theme
    ]


errorStyles : Theme -> Maybe String -> List (Element.Attribute msg)
errorStyles theme error =
    case error of
        Just errorMessage ->
            [ Border.color theme.colors.negative
            , Element.focused [ Border.color theme.colors.negative ]
            , Border.width 2
            , below
                (el
                    [ padding (Theme.smallPadding theme)
                    , Background.color (rgb 1 0.7 0.7)
                    , moveDown 5
                    , Theme.borderRounded theme
                    ]
                    (text errorMessage)
                )
            ]

        Nothing ->
            []


textInput : Theme -> List (Element.Attribute msg) -> TextInputConfig msg -> Maybe String -> Element msg
textInput theme attributes config error =
    Element.Input.text (defaultStyles theme ++ errorStyles theme error ++ attributes) config


searchInput : Theme -> List (Element.Attribute msg) -> TextInputConfig msg -> Element msg
searchInput theme attributes config =
    Element.Input.search (defaultStyles theme ++ attributes) config


checkBox : Theme -> List (Element.Attribute msg) -> CheckboxConfig msg -> Element msg
checkBox theme attributes config =
    Element.Input.checkbox (Border.color (rgba 0 0 0 0) :: attributes) { onChange = config.onChange, checked = config.checked, label = config.label, icon = Element.Input.defaultCheckbox }


multiLine : Theme -> List (Element.Attribute msg) -> MultilineTextInputConfig msg -> Maybe String -> Element msg
multiLine theme attributes config error =
    Element.Input.multiline (defaultStyles theme ++ errorStyles theme error ++ attributes) config
