module Morphir.Visual.Components.FieldList exposing (..)

import Element exposing (Element, centerY, el, fill, padding, shrink, spacingXY, table, text, width)
import Element.Border as Border
import Morphir.IR.Name exposing (Name)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Theme as Theme exposing (Theme)


view : Theme -> List ( Name, Element msg ) -> Element msg
view theme fields =
    table
        [ width fill
        , spacingXY 0 5
        ]
        { columns =
            [ { header = text ""
              , width = shrink
              , view =
                    \( fieldName, _ ) ->
                        el
                            [ width shrink
                            , centerY
                            , padding <| Theme.smallPadding theme
                            , Border.roundEach
                                { topLeft = 6
                                , bottomLeft = 6
                                , topRight = 0
                                , bottomRight = 0
                                }
                            ]
                            (text <| nameToText fieldName ++ " : ")
              }
            , { header = text ""
              , width = shrink
              , view =
                    \( _, fieldValue ) ->
                        fieldValue
              }
            ]
        , data =
            fields
        }
