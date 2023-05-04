module Morphir.Visual.Components.FieldList exposing (..)

import Element exposing (Element, centerY, el, fill, paddingXY, rgb, shrink, spacingXY, table, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Morphir.IR.Name exposing (Name)
import Morphir.Visual.Common exposing (nameToText)


view : List ( Name, Element msg ) -> Element msg
view fields =
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
                            [ width fill
                            , paddingXY 10 5
                            , centerY
                            , Font.color (rgb 1 1 1)
                            , Font.bold
                            , Background.color (rgb 0.2 0.3 0.4)
                            , Border.roundEach
                                { topLeft = 6
                                , bottomLeft = 6
                                , topRight = 0
                                , bottomRight = 0
                                }
                            ]
                            (text (nameToText fieldName))
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
