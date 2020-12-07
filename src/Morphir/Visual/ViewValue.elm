module Morphir.Visual.ViewValue exposing (view)

import Element exposing (Element, el, spacing, text)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Visual.Common exposing (cssClass, nameToText)
import Morphir.Visual.ViewApply as ViewApply
import Morphir.Visual.ViewField as ViewField
import Morphir.Visual.ViewIfThenElse as ViewIfThenElse
import Morphir.Visual.ViewLetDefinition as ViewLetDefinition
import Morphir.Visual.ViewList as ViewList
import Morphir.Visual.ViewLiteral as ViewLiteral
import Morphir.Visual.ViewReference as ViewReference


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

        Value.Reference tpe fQName ->
            ViewReference.view view fQName

        Value.Field tpe subjectValue fieldName ->
            ViewField.view view subjectValue fieldName

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

        Value.LetDefinition tpe _ _ _ ->
            let
                unnest : Value ta (Type ta) -> ( List ( Name, Value.Definition ta (Type ta) ), Value ta (Type ta) )
                unnest v =
                    case v of
                        Value.LetDefinition _ defName def inVal ->
                            let
                                ( defs, bottomIn ) =
                                    unnest inVal
                            in
                            ( ( defName, def ) :: defs, bottomIn )

                        notLet ->
                            ( [], notLet )

                ( definitions, inValue ) =
                    unnest value
            in
            ViewLetDefinition.view view definitions inValue

        Value.IfThenElse tpe condition thenBranch elseBranch ->
            ViewIfThenElse.view view condition thenBranch elseBranch

        _ ->
            Element.paragraph
                [ cssClass "todo"
                ]
                [ Element.text "???" ]
