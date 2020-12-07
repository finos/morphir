module Morphir.Visual.ViewLetDefinition exposing (..)

import Element exposing (Element, column, el, moveRight, spacing, text)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)


view : (Value ta (Type ta) -> Element msg) -> List ( Name, Value.Definition ta (Type ta) ) -> Value ta (Type ta) -> Element msg
view viewValue definitions inValue =
    column
        [ spacing 10 ]
        [ viewValue inValue
        , text "where"
        , column
            [ moveRight 10
            ]
            (definitions
                |> List.map
                    (\( defName, def ) ->
                        column
                            []
                            [ text (nameToText defName ++ " =")
                            , el
                                [ moveRight 10 ]
                                (viewValue def.body)
                            ]
                    )
            )
        ]
