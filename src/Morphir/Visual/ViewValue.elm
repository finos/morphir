module Morphir.Visual.ViewValue exposing (view)

import Element exposing (Element, el, spacing, text)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (cssClass, nameToText)
import Morphir.Visual.ViewApply as ViewApply
import Morphir.Visual.ViewIfThenElse as ViewIfThenElse
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

        Value.Variable tpe name ->
            el []
                (text (nameToText name))

        Value.Reference tpe (FQName packageName moduleName localName) ->
            String.join "."
                [ moduleName |> Path.toString Name.toTitleCase "."
                , localName |> Name.toCamelCase
                ]
                |> Element.text

        Value.Apply _ _ _ ->
            let
                uncurry : Value ta (Type ta) -> ( Value ta (Type ta), List (Value ta (Type ta)) )
                uncurry v =
                    case v of
                        Value.Apply _ fun arg ->
                            let
                                ( bottomFun, initArgs ) =
                                    uncurry fun
                            in
                            ( bottomFun, arg :: initArgs )

                        notApply ->
                            ( notApply, [] )

                ( function, argsReversed ) =
                    uncurry value
            in
            ViewApply.view view function (argsReversed |> List.reverse)

        Value.LetDefinition tpe bindingName bindingDef inValue ->
            ViewLetDefinition.view view bindingName bindingDef inValue

        Value.IfThenElse tpe condition thenBranch elseBranch ->
            ViewIfThenElse.view view condition thenBranch elseBranch

        _ ->
            Element.paragraph
                [ cssClass "todo"
                ]
                [ Element.text "???" ]
