module Morphir.Visual.ViewField exposing (..)

import Element exposing (Element, fill, row, text, width)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (nameToText)


view : (Value ta (Type ta) -> Element msg) -> Value ta (Type ta) -> Name -> Element msg
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
