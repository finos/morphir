module Morphir.Visual.ViewValue exposing (view, viewWithData)

import Dict exposing (Dict)
import Element exposing (Element, el, text)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name exposing (Name)
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
import Morphir.Visual.ViewTuple as ViewTuple


view : Value () (Type ()) -> Element msg
view value =
    let
        indexedValue : Value () ( Int, Type () )
        indexedValue =
            value
                |> Value.indexedMapValue
                    (\index va ->
                        ( index, va )
                    )
                    0
                |> Tuple.first
    in
    case value of
        Value.Literal literalType literal ->
            ViewLiteral.view literal

        Value.Tuple tpe elems ->
            ViewTuple.view view elems

        Value.List (Type.Reference _ (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "list" ] ] [ "list" ]) [ itemType ]) items ->
            ViewList.view view itemType items

        Value.Variable tpe name ->
            el []
                (text (nameToText name))

        Value.Reference tpe fQName ->
            ViewReference.view view fQName

        Value.Field tpe subjectValue fieldName ->
            ViewField.view view subjectValue fieldName

        Value.Apply _ fun arg ->
            let
                ( function, argsReversed ) =
                    Value.uncurryApply fun arg
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

        Value.IfThenElse _ _ _ _ ->
            ViewIfThenElse.view view value Dict.empty

        _ ->
            Element.paragraph
                [ cssClass "todo"
                ]
                [ Element.text "???" ]


viewWithData : Distribution -> Value.Definition () (Type ()) -> Dict Name (Value () ()) -> Element msg
viewWithData distribution valueDef argumentValues =
    let
        indexedValue : Value () ( Int, Type () )
        indexedValue =
            valueDef.body
                |> Value.indexedMapValue
                    (\index va ->
                        ( index, va )
                    )
                    0
                |> Tuple.first
    in
    case valueDef.body of
        Value.IfThenElse _ _ _ _ ->
            ViewIfThenElse.view view valueDef.body argumentValues

        _ ->
            Element.text "view with data"
