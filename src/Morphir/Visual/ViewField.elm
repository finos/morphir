module Morphir.Visual.ViewField exposing (..)

import Element exposing (Element, fill, row, text, width)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.VisualTypedValue exposing (VisualTypedValue)


view : (VisualTypedValue -> Element msg) -> VisualTypedValue -> Name -> Element msg
view viewValue subjectValue fieldName =
    case subjectValue of
        Value.Variable _ variableName ->
            String.concat
                [ "the "
                , nameToText variableName
                , "'s "
                , nameToText fieldName
                ]
                |> text

        _ ->
            row
                [ width fill ]
                [ String.concat
                    [ "the "
                    , nameToText fieldName
                    , " field of "
                    ]
                    |> text
                , viewValue subjectValue
                ]
