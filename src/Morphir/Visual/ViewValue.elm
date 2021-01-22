module Morphir.Visual.ViewValue exposing (viewDefinition)

import Dict exposing (Dict)
import Element exposing (Element, el, spacing, text)
import Element.Background
import Element.Border
import Element.Events exposing (onClick)
import Element.Font as Font exposing (..)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.FQName exposing (FQName(..))
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value)
import Morphir.Value.Interpreter exposing (FQN)
import Morphir.Visual.BoolOperatorTree as BoolOperatorTree exposing (BoolOperatorTree)
import Morphir.Visual.Common exposing (cssClass, nameToText)
import Morphir.Visual.Context as Context exposing (Context)
import Morphir.Visual.ViewApply as ViewApply
import Morphir.Visual.ViewBoolOperatorTree as ViewBoolOperatorTree
import Morphir.Visual.ViewField as ViewField
import Morphir.Visual.ViewIfThenElse as ViewIfThenElse
import Morphir.Visual.ViewLetDefinition as ViewLetDefinition
import Morphir.Visual.ViewList as ViewList
import Morphir.Visual.ViewLiteral as ViewLiteral
import Morphir.Visual.ViewReference as ViewReference
import Morphir.Visual.ViewTuple as ViewTuple
import Morphir.Web.Theme.Light exposing (blue)


viewDefinition : Distribution -> Value.Definition () (Type ()) -> Dict Name RawValue -> (FQN -> Bool -> msg) -> Dict FQN (Value.Definition () (Type ())) -> Element msg
viewDefinition distribution valueDef variables onReferenceClicked expandedFunctions =
    let
        ctx : Context msg
        ctx =
            Context.fromDistributionAndVariables distribution variables onReferenceClicked
    in
    Element.column [ spacing 8 ]
        [ viewValue ctx variables valueDef.body
        , Element.column
            [ spacing 10 ]
            [ text "where"
            , Element.column
                [ spacing 20
                ]
                (expandedFunctions
                    |> Dict.toList
                    |> List.reverse
                    |> List.map
                        (\( ( _, _, localName ) as fqName, valDef ) ->
                            Element.column
                                [ spacing 10
                                ]
                                [ text (nameToText localName ++ " =")
                                , el
                                    []
                                    (viewValue ctx Dict.empty valDef.body)
                                , Element.column
                                    [ Font.bold
                                    , Element.Border.solid
                                    , Element.Border.width 10
                                    , Element.Border.rounded 5
                                    , Element.Background.color blue
                                    , onClick (ctx.onReferenceClicked fqName True)
                                    ]
                                    [ Element.text "RollBack" ]
                                ]
                        )
                )
            ]
        ]


viewValue : Context msg -> Dict Name RawValue -> TypedValue -> Element msg
viewValue ctx argumentValues value =
    viewValueByValueType ctx argumentValues value


viewValueByValueType : Context msg -> Dict Name RawValue -> TypedValue -> Element msg
viewValueByValueType ctx argumentValues typedValue =
    let
        valueType : Type ()
        valueType =
            Value.valueAttribute typedValue
    in
    if valueType == Basics.boolType () then
        let
            boolOperatorTree : BoolOperatorTree
            boolOperatorTree =
                BoolOperatorTree.fromTypedValue typedValue
        in
        ViewBoolOperatorTree.view (viewValueByLanguageFeature ctx argumentValues) boolOperatorTree

    else
        viewValueByLanguageFeature ctx argumentValues typedValue


viewValueByLanguageFeature : Context msg -> Dict Name RawValue -> TypedValue -> Element msg
viewValueByLanguageFeature ctx argumentValues value =
    case value of
        Value.Literal literalType literal ->
            ViewLiteral.view literal

        Value.Constructor tpe fQName ->
            ViewReference.view ctx (viewValue ctx argumentValues) fQName

        Value.Tuple tpe elems ->
            ViewTuple.view (viewValue ctx argumentValues) elems

        Value.List (Type.Reference _ (FQName [ [ "morphir" ], [ "s", "d", "k" ] ] [ [ "list" ] ] [ "list" ]) [ itemType ]) items ->
            ViewList.view ctx.distribution (viewValue ctx argumentValues) itemType items

        Value.Variable tpe name ->
            el []
                (text (nameToText name))

        Value.Reference tpe fQName ->
            ViewReference.view ctx (viewValue ctx argumentValues) fQName

        Value.Field tpe subjectValue fieldName ->
            ViewField.view (viewValue ctx argumentValues) subjectValue fieldName

        Value.Apply _ fun arg ->
            let
                ( function, args ) =
                    Value.uncurryApply fun arg
            in
            ViewApply.view (viewValue ctx argumentValues) function args

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
            ViewLetDefinition.view (viewValue ctx argumentValues) definitions inValue

        Value.IfThenElse _ _ _ _ ->
            ViewIfThenElse.view ctx (viewValue ctx argumentValues) value Dict.empty

        _ ->
            Element.paragraph
                [ cssClass "todo"
                ]
                [ Element.text "???" ]
