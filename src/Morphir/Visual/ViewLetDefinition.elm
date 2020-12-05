module Morphir.Visual.ViewLetDefinition exposing (..)

import Element exposing (Element, spacing)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


view : (Value ta (Type ta) -> Element msg) -> Name -> Value.Definition ta (Type ta) -> Value ta (Type ta) -> Element msg
view viewValue bindingName bindingDef inValue =
    Element.column
        [ spacing 10 ]
        [ viewValue inValue
        , Element.text "where"
        , Element.text ((bindingName |> Name.toHumanWords |> String.join " ") ++ " = ")
        , viewValue bindingDef.body
        ]
