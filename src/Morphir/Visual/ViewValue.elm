module Morphir.Visual.ViewValue exposing (..)

import Element exposing (Element, spacing)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (cssClass)
import Morphir.Visual.ViewLetDefinition as ViewLetDefinition
import Morphir.Visual.ViewList as ViewList
import Morphir.Visual.ViewLiteral as ViewLiteral


view : Value ta (Type ta) -> Element msg
view value =
    case value of
        Value.Literal literalType literal ->
            ViewLiteral.view literal

        Value.List (Type.Reference _ (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "list" ] ] [ "list" ]) [ itemType ]) items ->
            ViewList.view view itemType items

        Value.Reference tpe (FQName packageName moduleName localName) ->
            String.join "."
                [ moduleName |> Path.toString Name.toTitleCase "."
                , localName |> Name.toCamelCase
                ]
                |> Element.text

        Value.Apply tpe funValue argValue ->
            Element.column
                [ spacing 10 ]
                [ view funValue
                , view argValue
                ]

        Value.LetDefinition tpe bindingName bindingDef inValue ->
            ViewLetDefinition.view view bindingName bindingDef inValue

        _ ->
            Element.paragraph
                [ cssClass "todo"
                ]
                [ Element.text "???" ]
