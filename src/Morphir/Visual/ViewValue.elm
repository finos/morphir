module Morphir.Visual.ViewValue exposing (viewDefinition)

import Dict exposing (Dict)
import Element exposing (Element, centerX, el, fill, padding, rgb, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events exposing (onClick)
import Element.Font as Font exposing (..)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, TypedValue, Value)
import Morphir.Visual.BoolOperatorTree as BoolOperatorTree exposing (BoolOperatorTree)
import Morphir.Visual.Common exposing (definition, nameToText)
import Morphir.Visual.Components.AritmeticExpressions as ArithmeticOperatorTree exposing (ArithmeticOperatorTree)
import Morphir.Visual.Config as Config exposing (Config)
import Morphir.Visual.Theme exposing (mediumSpacing, smallPadding, smallSpacing)
import Morphir.Visual.ViewApply as ViewApply
import Morphir.Visual.ViewArithmetic as ViewArithmetic
import Morphir.Visual.ViewBoolOperatorTree as ViewBoolOperatorTree
import Morphir.Visual.ViewField as ViewField
import Morphir.Visual.ViewIfThenElse as ViewIfThenElse
import Morphir.Visual.ViewList as ViewList
import Morphir.Visual.ViewLiteral as ViewLiteral
import Morphir.Visual.ViewReference as ViewReference
import Morphir.Visual.ViewTuple as ViewTuple
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.Theme.Light exposing (gray)


viewDefinition : Config msg -> FQName -> Value.Definition () (Type ()) -> Element msg
viewDefinition config ( _, _, valueName ) valueDef =
    let
        _ =
            Debug.log "variables" config.state.variables
    in
    Element.column [ mediumSpacing config.state.theme |> spacing ]
        [ definition config
            (nameToText valueName)
            (viewValue config valueDef.body)
        , if Dict.isEmpty config.state.expandedFunctions then
            Element.none

          else
            Element.column
                [ mediumSpacing config.state.theme |> spacing ]
                (config.state.expandedFunctions
                    |> Dict.toList
                    |> List.reverse
                    |> List.map
                        (\( ( _, _, localName ) as fqName, valDef ) ->
                            Element.column
                                [ smallSpacing config.state.theme |> spacing ]
                                [ definition config (nameToText localName) (viewValue config valDef.body)
                                , Element.el
                                    [ Font.bold
                                    , Border.solid
                                    , Border.rounded 4
                                    , Background.color gray
                                    , smallPadding config.state.theme |> padding
                                    , smallSpacing config.state.theme |> spacing
                                    , onClick (config.handlers.onReferenceClicked fqName True)
                                    ]
                                    (Element.text "Close")
                                ]
                        )
                )
        ]


viewValue : Config msg -> TypedValue -> Element msg
viewValue config value =
    viewValueByValueType config value


viewValueByValueType : Config msg -> TypedValue -> Element msg
viewValueByValueType config typedValue =
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
        ViewBoolOperatorTree.view config (viewValueByLanguageFeature config) boolOperatorTree

    else if Basics.isNumber valueType then
        let
            arithmeticOperatorTree : ArithmeticOperatorTree
            arithmeticOperatorTree =
                ArithmeticOperatorTree.fromArithmeticTypedValue typedValue
        in
        ViewArithmetic.view config (viewValueByLanguageFeature config) arithmeticOperatorTree

    else
        viewValueByLanguageFeature config typedValue


viewValueByLanguageFeature : Config msg -> TypedValue -> Element msg
viewValueByLanguageFeature config value =
    let
        valueElem : Element msg
        valueElem =
            case value of
                Value.Literal literalType literal ->
                    ViewLiteral.view literal

                Value.Constructor tpe fQName ->
                    ViewReference.view config (viewValue config) fQName

                Value.Tuple tpe elems ->
                    ViewTuple.view config (viewValue config) elems

                Value.List (Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ itemType ]) items ->
                    ViewList.view config (viewValue config) itemType items

                Value.Variable tpe name ->
                    el [ width Element.fill, center]
                        (text (nameToText name))

                Value.Reference tpe fQName ->
                    ViewReference.view config (viewValue config) fQName

                Value.Field tpe subjectValue fieldName ->
                    ViewField.view (viewValue config) subjectValue fieldName

                Value.Apply _ fun arg ->
                    let
                        ( function, args ) =
                            Value.uncurryApply fun arg
                    in
                    ViewApply.view config (viewValue config) function args

                Value.LetDefinition tpe _ _ _ ->
                    let
                        unnest : Config msg -> Value () (Type ()) -> ( List ( Name, Element msg ), Element msg )
                        unnest conf v =
                            case v of
                                Value.LetDefinition _ defName def inVal ->
                                    let
                                        currentState =
                                            conf.state

                                        newState =
                                            { currentState
                                                | variables =
                                                    conf
                                                        |> Config.evaluate
                                                            (def
                                                                |> Value.mapDefinitionAttributes (always ()) (always ())
                                                                |> Value.definitionToValue
                                                            )
                                                        |> Result.map
                                                            (\evaluatedDefValue ->
                                                                currentState.variables
                                                                    |> Dict.insert defName evaluatedDefValue
                                                            )
                                                        |> Result.withDefault currentState.variables
                                            }

                                        ( defs, bottomIn ) =
                                            unnest { conf | state = newState } inVal
                                    in
                                    ( ( defName, viewValue conf def.body ) :: defs, bottomIn )

                                notLet ->
                                    ( [], viewValue conf notLet )

                        ( definitions, inValueElem ) =
                            unnest config value
                    in
                    Element.column
                        [ mediumSpacing config.state.theme |> spacing ]
                        [ inValueElem
                        , Element.column
                            [ mediumSpacing config.state.theme |> spacing ]
                            (definitions
                                |> List.map
                                    (\( defName, defElem ) ->
                                        Element.column
                                            [ mediumSpacing config.state.theme |> spacing ]
                                            [ definition config (nameToText defName) defElem ]
                                    )
                            )
                        ]

                Value.IfThenElse _ _ _ _ ->
                    ViewIfThenElse.view config (viewValue config) value

                other ->
                    Element.column
                        [ Background.color (rgb 1 0.6 0.6)
                        , smallPadding config.state.theme |> padding
                        , Border.rounded 6
                        ]
                        [ Element.el
                            [ smallPadding config.state.theme |> padding
                            , Font.bold
                            ]
                            (Element.text "No visual mapping found for:")
                        , Element.el
                            [ Background.color (rgb 1 1 1)
                            , smallPadding config.state.theme |> padding
                            , Border.rounded 6
                            , width fill
                            ]
                            (XRayView.viewValue XRayView.viewType other)
                        ]
    in
    valueElem
