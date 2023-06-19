module Morphir.Visual.ViewApply exposing (view)

import Dict exposing (Dict)
import Element exposing (Element, above, centerX, centerY, el, fill, htmlAttribute, moveUp, padding, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Elm.RawFile exposing (moduleName)
import Html.Attributes exposing (style, value)
import Morphir.IR as IR
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (RawValue, Value(..), toRawValue)
import Morphir.Type.Infer as Infer
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Interpreter exposing (evaluateFunctionValue, evaluateValue)
import Morphir.Visual.Common exposing (nameToText, tooltip)
import Morphir.Visual.Components.DrillDownPanel as DrillDownPanel exposing (Depth)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config, DrillDownFunctions(..), drillDownContains, evalIfPathTaken)
import Morphir.Visual.EnrichedValue exposing (EnrichedValue, fromRawValue, getId, toTypedValue)
import Morphir.Visual.Theme as Theme exposing (borderRounded, smallPadding, smallSpacing)
import Morphir.Visual.ViewList as ViewList


view : Config msg -> (Config msg -> Value.Definition () (Type ()) -> Element msg) -> (EnrichedValue -> Element msg) -> EnrichedValue -> List EnrichedValue -> Element msg
view config viewDefinitionBody viewValue functionValue argValues =
    let
        styles : List (Element.Attribute msg)
        styles =
            [ smallSpacing config.state.theme |> spacing, Element.centerY ]

        binaryOperatorStyles : List (Element.Attribute msg)
        binaryOperatorStyles =
            [ Background.color config.state.theme.colors.lightGray
            , borderRounded config.state.theme
            ]
                ++ styles

        drillDownPanel : FQName -> Depth -> Element msg -> Element msg -> Element msg -> Bool -> Element msg
        drillDownPanel fqName depth closedElement openHeader openElement isOpen =
            DrillDownPanel.drillDownPanel config.state.theme
                { openMsg = config.handlers.onReferenceClicked fqName (getId functionValue) config.nodePath
                , closeMsg = config.handlers.onReferenceClose fqName (getId functionValue) config.nodePath
                , depth = depth
                , closedElement = closedElement
                , openElement = openElement
                , openHeader = openHeader
                , isOpen = isOpen
                , zIndex = config.state.zIndex - 2
                }

        viewFunctionValue : FQName -> Element msg
        viewFunctionValue fqName =
            el [ tooltip above (functionOutput fqName) ] <| viewValue functionValue

        viewArgumentList : List (Element msg)
        viewArgumentList =
            argValues
                |> List.indexedMap
                    (\ind v ->
                        case v of
                            Value.Reference _ _ ->
                                viewValue v

                            Value.Apply _ _ _ ->
                                viewValue v

                            _ ->
                                el
                                    [ Background.color config.state.theme.colors.lightGray
                                    , borderRounded config.state.theme
                                    , padding (Theme.scaled -4 config.state.theme)
                                    ]
                                    (viewValue v)
                    )

        functionOutput : FQName -> Element msg
        functionOutput fqName =
            let
                variables : List (Maybe RawValue)
                variables =
                    case Dict.get fqName config.ir.valueDefinitions of
                        Just valueDef ->
                            Dict.fromList (List.map2 (\( name, _, _ ) argValue -> ( name, argValue |> evalIfPathTaken config )) valueDef.inputTypes argValues) |> Dict.values

                        Nothing ->
                            []

                viewRawValue : RawValue -> Element msg
                viewRawValue rawValue =
                    case fromRawValue config.ir rawValue of
                        Ok typedValue ->
                            el [ centerY ] (viewValue typedValue)

                        Err error ->
                            el [ centerX, centerY ] (text (Infer.typeErrorToMessage error))

                popupstyles : List (Element.Attribute msg)
                popupstyles =
                    [ Background.color config.state.theme.colors.lightest
                    , Font.bold
                    , Font.center
                    , config.state.theme |> borderRounded
                    , Border.width 1
                    , smallPadding config.state.theme |> padding
                    ]
            in
            case evaluateFunctionValue config.nativeFunctions config.ir fqName variables of
                Ok value ->
                    el popupstyles (viewRawValue value)

                Err firstError ->
                    case firstError of
                        ReferenceNotFound _ ->
                            case evaluateValue config.nativeFunctions config.ir config.state.variables (List.map toRawValue argValues) (toRawValue functionValue) of
                                Ok value ->
                                    el popupstyles (viewRawValue value)

                                Err err ->
                                    Element.none

                        _ ->
                            Element.none
    in
    case ( functionValue, argValues ) of
        ( (Value.Constructor _ fQName) as constr, _ ) ->
            case config.ir |> IR.lookupTypeSpecification (config.ir |> IR.resolveAliases fQName) of
                Just (Type.TypeAliasSpecification _ (Type.Record _ fields)) ->
                    FieldList.view
                        (List.map2
                            (\field arg ->
                                ( field.name
                                , Element.el [ smallPadding config.state.theme |> padding, Element.centerY ] (viewValue arg)
                                )
                            )
                            fields
                            argValues
                        )

                _ ->
                    Element.row [] (viewValue constr :: (argValues |> List.map viewValue))

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "negate" ] ), [ argValue ] ) ->
            row binaryOperatorStyles
                [ text "- ("
                , viewValue argValue
                , text ")"
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "abs" ] ), [ argValue ] ) ->
            row binaryOperatorStyles
                [ text "abs ("
                , viewValue argValue
                , text ")"
                ]

        ( Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], localName ), [ argValue ] ) ->
            row ((smallPadding config.state.theme |> padding) :: binaryOperatorStyles)
                [ text ((localName |> Name.toCamelCase) ++ " (")
                , viewValue argValue
                , text ")"
                ]

        -- possibly binary operator
        ( Value.Reference _ (( [ [ "morphir" ], [ "s", "d", "k" ] ], moduleName, localName ) as fqName), [ argValues1, argValues2 ] ) ->
            let
                functionName : String
                functionName =
                    String.join "."
                        [ moduleName |> Path.toString Name.toTitleCase "."
                        , localName |> Name.toCamelCase
                        ]
            in
            if moduleName == [ [ "basics" ] ] && (localName == [ "min" ] || localName == [ "max" ]) then
                row
                    binaryOperatorStyles
                    [ viewFunctionValue fqName
                    , text " ("
                    , viewValue argValues1
                    , text ","
                    , viewValue argValues2
                    , text ")"
                    ]

            else if moduleName == [ [ "basics" ] ] && (localName == [ "power" ]) then
                row
                    binaryOperatorStyles
                    [ viewValue argValues1
                    , el [ Font.bold, Font.size (ceiling (toFloat config.state.theme.fontSize / 1.3)), moveUp (toFloat (config.state.theme.fontSize // 4)) ] (viewValue argValues2)
                    ]

            else if moduleName == [ [ "list" ] ] && (localName == [ "member" ]) then
                case argValues2 of
                    Value.List ( _, Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ itemType ] ) items ->
                        row
                            styles
                            [ viewValue argValues1
                            , el [ Font.bold ] <| text "is one of"
                            , ViewList.view config viewValue itemType items (Just argValues1)
                            ]

                    _ ->
                        row
                            styles
                            [ viewValue argValues1
                            , el [ Font.bold ] <| text "is one of"
                            , viewValue argValues2
                            ]

            else
                case Dict.get functionName inlineBinaryOperators of
                    Just string ->
                        row
                            ((smallPadding config.state.theme |> padding) :: styles)
                            [ viewValue argValues1
                            , text string
                            , viewValue argValues2
                            ]

                    Nothing ->
                        row
                            ([ Border.color config.state.theme.colors.gray, Border.width 1, smallPadding config.state.theme |> padding ] ++ styles)
                            (viewFunctionValue fqName :: viewArgumentList)

        ( Value.Reference _ fqName, _ ) ->
            let
                argList : Element msg
                argList =
                    row [ width fill, centerX, smallSpacing config.state.theme |> spacing ]
                        viewArgumentList

                drillDown : DrillDownFunctions -> List Int -> Maybe (Value.Definition () (Type ()))
                drillDown dict nodePath =
                    if drillDownContains dict (getId functionValue) nodePath then
                        Dict.get fqName config.ir.valueDefinitions

                    else
                        Nothing

                ( _, _, valueName ) =
                    fqName

                {-
                   Reverse the order of fQName and arguments if the function starts with is, to improve readability
                   "is foo x" -> "x is foo"
                -}
                reverseIfStartsWithIs : List a -> List a
                reverseIfStartsWithIs l =
                    if (List.head valueName |> Maybe.withDefault "") == "is" then
                        List.reverse l

                    else
                        identity l

                closedElement : Element msg
                closedElement =
                    row [ smallSpacing config.state.theme |> spacing ]
                        ([ el [ Background.color <| config.state.theme.colors.selectionColor, smallPadding config.state.theme |> padding ] (text (nameToText valueName))
                         , argList
                         ]
                            |> reverseIfStartsWithIs
                        )

                openElement : Element msg
                openElement =
                    case drillDown config.state.drillDownFunctions config.nodePath of
                        Just valueDef ->
                            let
                                mapping : Dict Name.Name Value.TypedValue
                                mapping =
                                    List.map2 (\val originalName -> ( originalName, toTypedValue val ))
                                        argValues
                                        (List.map (\( name, _, _ ) -> name) valueDef.inputTypes)
                                        |> Dict.fromList
                            in
                            viewDefinitionBody { config | nodePath = config.nodePath ++ [ getId functionValue ] } { valueDef | body = Value.replaceVariables (Value.rewriteMaybeToPatternMatch valueDef.body) mapping }

                        Nothing ->
                            Element.none

                openHeader : Element msg
                openHeader =
                    row [ smallSpacing config.state.theme |> spacing ]
                        [ el [ Background.color <| config.state.theme.colors.selectionColor, smallPadding config.state.theme |> padding ] (text (nameToText valueName))
                        ]
            in
            drillDownPanel fqName (List.length config.nodePath) closedElement openHeader openElement (drillDownContains config.state.drillDownFunctions (getId functionValue) config.nodePath)

        _ ->
            row ([ Border.color config.state.theme.colors.gray, Border.width 1, smallPadding config.state.theme |> padding, config.state.theme |> borderRounded ] ++ styles)
                [ viewFunctionValue ( [], [], [] )
                , row [ width fill, centerX, smallSpacing config.state.theme |> spacing ]
                    viewArgumentList
                ]


inlineBinaryOperators : Dict String String
inlineBinaryOperators =
    Dict.fromList
        [ ( "Basics.equal", "=" )
        , ( "Basics.lessThan", "<" )
        , ( "Basics.lessThanOrEqual", "<=" )
        , ( "Basics.greaterThan", ">" )
        , ( "Basics.greaterThanOrEqual", ">=" )
        , ( "Basics.add", "+" )
        , ( "Basics.subtract", "-" )
        , ( "Basics.multiply", "*" )
        , ( "Basics.divide", "/" )
        , ( "List.append", "+" )
        , ( "Basics.notEqual", "≠" )
        , ( "Basics.power", "^" )
        ]
