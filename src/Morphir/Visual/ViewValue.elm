module Morphir.Visual.ViewValue exposing (viewDefinition)

import Dict exposing (Dict)
import Element exposing (Element, el, fill, rgb, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font exposing (..)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value)
import Morphir.Visual.BoolOperatorTree as BoolOperatorTree exposing (BoolOperatorTree)
import Morphir.Visual.Common exposing (nameToText)
import Morphir.Visual.Components.AritmeticExpressions as ArithmeticOperatorTree exposing (ArithmeticOperatorTree)
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.ViewApply as ViewApply
import Morphir.Visual.ViewArithmetic as ViewArithmetic
import Morphir.Visual.ViewBoolOperatorTree as ViewBoolOperatorTree
import Morphir.Visual.ViewField as ViewField
import Morphir.Visual.ViewIfThenElse as ViewIfThenElse
import Morphir.Visual.ViewLetDefinition as ViewLetDefinition
import Morphir.Visual.ViewList as ViewList
import Morphir.Visual.ViewLiteral as ViewLiteral
import Morphir.Visual.ViewReference as ViewReference
import Morphir.Visual.ViewTuple as ViewTuple
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.Theme.Light exposing (gray)


viewDefinition : Config msg -> Value.Definition () (Type ()) -> Dict Name RawValue -> Element msg
viewDefinition config valueDef variables =
    Element.column [ spacing 8 ]
        [ viewValue config variables valueDef.body
        , if Dict.isEmpty config.state.expandedFunctions then
            Element.none

          else
            Element.column
                [ spacing 10 ]
                [ Element.el [ Font.bold ] (Element.text "where")
                , Element.column
                    [ spacing 20
                    ]
                    (config.state.expandedFunctions
                        |> Dict.toList
                        |> List.reverse
                        |> List.map
                            (\( ( _, _, localName ) as fqName, valDef ) ->
                                Element.column
                                    [ spacing 10
                                    ]
                                    [ Element.el [ Font.bold ] (text (nameToText localName ++ " ="))
                                    , el
                                        []
                                        (viewValue config Dict.empty valDef.body)
                                    , Element.column
                                        [ Font.bold
                                        , Border.solid
                                        , Border.rounded 5
                                        , Background.color gray
                                        , Element.padding 10
                                        , onClick (config.handlers.onReferenceClicked fqName True)
                                        ]
                                        [ Element.text "Close" ]
                                    ]
                            )
                    )
                ]
        ]


viewValue : Config msg -> Dict Name RawValue -> TypedValue -> Element msg
viewValue config argumentValues value =
    viewValueByValueType config argumentValues value


viewValueByValueType : Config msg -> Dict Name RawValue -> TypedValue -> Element msg
viewValueByValueType config argumentValues typedValue =
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
        ViewBoolOperatorTree.view (viewValueByLanguageFeature config argumentValues) boolOperatorTree

    else if Basics.isNumber valueType then
        let
            arithmeticOperatorTree : ArithmeticOperatorTree
            arithmeticOperatorTree =
                ArithmeticOperatorTree.fromArithmeticTypedValue typedValue
        in
        ViewArithmetic.view (viewValueByLanguageFeature config argumentValues) arithmeticOperatorTree

    else
        viewValueByLanguageFeature config argumentValues typedValue


viewValueByLanguageFeature : Config msg -> Dict Name RawValue -> TypedValue -> Element msg
viewValueByLanguageFeature config argumentValues value =
    case value of
        Value.Literal literalType literal ->
            ViewLiteral.view literal

        Value.Constructor tpe fQName ->
            ViewReference.view config (viewValue config argumentValues) fQName

        Value.Tuple tpe elems ->
            ViewTuple.view (viewValue config argumentValues) elems

        Value.List (Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ itemType ]) items ->
            ViewList.view config (viewValue config argumentValues) itemType items

        Value.Variable tpe name ->
            el []
                (text (nameToText name))

        Value.Reference tpe fQName ->
            ViewReference.view config (viewValue config argumentValues) fQName

        Value.Field tpe subjectValue fieldName ->
            ViewField.view (viewValue config argumentValues) subjectValue fieldName

        Value.Apply _ fun arg ->
            let
                ( function, args ) =
                    Value.uncurryApply fun arg
            in
            ViewApply.view (viewValue config argumentValues) function args

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
            ViewLetDefinition.view (viewValue config argumentValues) definitions inValue

        Value.IfThenElse _ _ _ _ ->
            ViewIfThenElse.view config (viewValue config argumentValues) value Dict.empty

        other ->
            Element.column
                [ Background.color (rgb 1 0.6 0.6)
                , Element.padding 5
                , Border.rounded 3
                ]
                [ Element.el
                    [ Element.padding 5
                    , Font.bold

                    --, Font.color (rgb 1 1 1)
                    ]
                    (Element.text "No visual mapping found for:")
                , Element.el
                    [ Background.color (rgb 1 1 1)
                    , Element.padding 5
                    , Border.rounded 3
                    , width fill
                    ]
                    (XRayView.viewValue XRayView.viewType other)
                ]
