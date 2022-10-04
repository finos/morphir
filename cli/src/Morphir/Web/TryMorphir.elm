module Morphir.Web.TryMorphir exposing (..)

import Browser
import Dict exposing (Dict)
import Element exposing (Element, alignRight, column, el, fill, height, layout, none, padding, paddingEach, paddingXY, paragraph, px, rgb, row, scrollbars, shrink, spacing, table, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Json.Encode as Encode
import Morphir.Compiler as Compiler
import Morphir.Elm.Frontend as Frontend exposing (SourceFile)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName exposing (FQName, fqn)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.Codec as TypeCodec
import Morphir.IR.Value as Value
import Morphir.IR.Value.Codec as ValueCodec
import Morphir.Type.Constraint exposing (Constraint(..))
import Morphir.Type.ConstraintSet as ConstraintSet exposing (ConstraintSet)
import Morphir.Type.Count as Count
import Morphir.Type.Infer as Infer
import Morphir.Type.MetaType exposing (MetaType(..))
import Morphir.Type.Solve as Solve exposing (SolutionMap)
import Morphir.Visual.Common exposing (nameToText, pathToUrl)
import Morphir.Visual.Components.FieldList as FieldList
import Morphir.Visual.Config exposing (Config)
import Morphir.Visual.Theme as Theme
import Morphir.Visual.ValueEditor as ValueEditor
import Morphir.Visual.ViewValue as ViewValue
import Morphir.Visual.XRayView as XRayView
import Morphir.Web.SourceEditor as SourceEditor



-- MAIN


type alias Flags =
    {}


main =
    Browser.element { init = init, update = update, view = view, subscriptions = subscriptions }



-- MODEL


type alias Model =
    { source : String
    , maybePackageDef : Maybe (Package.Definition () (Type ()))
    , errors : List Compiler.Error
    , irView : IRView
    , valueStates : Dict FQName ValueState
    }


type IRView
    = InsightView
    | IRView


type alias ValueState =
    { typeInferenceStep : Int
    }


init : Flags -> ( Model, Cmd Msg )
init _ =
    update (ChangeSource sampleSource) { source = "", maybePackageDef = Nothing, errors = [], irView = IRView, valueStates = Dict.empty }


moduleSource : String -> SourceFile
moduleSource sourceValue =
    { path = "Test.elm"
    , content = sourceValue
    }



-- UPDATE


type Msg
    = ChangeSource String
    | ChangeIRView IRView
    | UpdateInferStep FQName Int
    | DoNothing


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ChangeSource sourceCode ->
            let
                opts =
                    { typesOnly = False }

                sourceFiles =
                    [ { path = "Test.elm"
                      , content = sampleSourcePrefix ++ sourceCode
                      }
                    ]

                frontendResult : Result (List Compiler.Error) (Package.Definition Frontend.SourceLocation Frontend.SourceLocation)
                frontendResult =
                    Frontend.mapSource opts packageInfo Dict.empty sourceFiles

                typedResult : Result (List Compiler.Error) (Package.Definition () (Type ()))
                typedResult =
                    frontendResult
                        |> Result.andThen
                            (\packageDef ->
                                let
                                    thisPackageSpec : Package.Specification ()
                                    thisPackageSpec =
                                        packageDef
                                            |> Package.definitionToSpecificationWithPrivate
                                            |> Package.mapSpecificationAttributes (\_ -> ())

                                    ir : IR
                                    ir =
                                        Frontend.defaultDependencies
                                            |> Dict.insert packageInfo.name thisPackageSpec
                                            |> IR.fromPackageSpecifications
                                in
                                packageDef
                                    --|> Package.mapDefinitionAttributes (\_ -> ()) identity
                                    --|> Infer.inferPackageDefinition ir
                                    --|> Result.map (Package.mapDefinitionAttributes (\_ -> ()) (\( _, tpe ) -> tpe))
                                    |> Package.mapDefinitionAttributes (\_ -> ()) (\_ -> Type.Unit ())
                                    |> Ok
                            )
            in
            ( { model
                | source = sourceCode
                , maybePackageDef =
                    case typedResult of
                        Ok newPackageDef ->
                            Just newPackageDef

                        Err _ ->
                            model.maybePackageDef
                , errors =
                    case typedResult of
                        Err errors ->
                            errors

                        Ok _ ->
                            []
              }
            , Cmd.none
            )

        ChangeIRView viewType ->
            ( { model
                | irView = viewType
              }
            , Cmd.none
            )

        DoNothing ->
            ( model, Cmd.none )

        UpdateInferStep fQName updated ->
            let
                newValueStates : Dict FQName { typeInferenceStep : Int }
                newValueStates =
                    model.valueStates
                        |> Dict.update fQName
                            (\maybeValueState ->
                                case maybeValueState of
                                    Just valueState ->
                                        Just { valueState | typeInferenceStep = updated }

                                    Nothing ->
                                        Just { typeInferenceStep = updated }
                            )
            in
            ( { model | valueStates = newValueStates }, Cmd.none )



-- VIEW


view : Model -> Html Msg
view model =
    layout
        [ width fill
        , height fill
        , Font.family
            [ Font.external
                { name = "Source Code Pro"
                , url = "https://fonts.googleapis.com/css2?family=Source+Code+Pro&display=swap"
                }
            , Font.monospace
            ]
        , Font.size 16
        ]
        (el
            [ width fill
            , height fill
            ]
            (viewPackageResult model ChangeSource)
        )


viewPackageResult : Model -> (String -> Msg) -> Element Msg
viewPackageResult model onSourceChange =
    row
        [ width fill
        , height fill
        , scrollbars
        ]
        [ column
            [ width fill
            , height fill
            , scrollbars
            ]
            [ el [ height shrink, padding 10 ] (text "Source Model")
            , el
                [ width fill
                , height fill
                , scrollbars
                ]
                (SourceEditor.view model.source onSourceChange)
            , el
                [ height shrink
                , width fill
                , padding 10
                , Background.color
                    (if List.isEmpty model.errors then
                        rgb 0.5 0.7 0.5

                     else
                        rgb 0.7 0.5 0.5
                    )
                ]
                (if List.isEmpty model.errors then
                    text "Parsed > Resolved > Type checked"

                 else
                    model.errors
                        |> List.concatMap
                            (\error ->
                                case error of
                                    Compiler.ErrorsInSourceFile _ sourceErrors ->
                                        sourceErrors
                                            |> List.map (.errorMessage >> text >> List.singleton >> paragraph [])

                                    Compiler.ErrorAcrossSourceFiles e ->
                                        [ Debug.toString e |> text ]
                            )
                        |> column []
                )
            ]
        , column
            [ width fill
            , height fill
            , scrollbars
            ]
            [ row [ width fill ]
                [ el [ height shrink, padding 10 ] (text "Morphir IR")
                , viewIRViewTabs model.irView
                ]
            , el
                [ width fill
                , height fill
                , scrollbars
                , padding 10
                ]
                (case model.maybePackageDef of
                    Just packageDef ->
                        viewPackageDefinition model (\_ -> Html.div [] []) packageDef

                    Nothing ->
                        Element.none
                )
            ]
        ]


viewPackageDefinition : Model -> (va -> Html Msg) -> Package.Definition () (Type ()) -> Element Msg
viewPackageDefinition model viewAttribute packageDef =
    let
        packageName : PackageName
        packageName =
            [ [ "my" ] ]

        ir : IR
        ir =
            IR.fromDistribution
                (Library packageName Dict.empty packageDef)
    in
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( moduleName, moduleDef ) ->
                viewModuleDefinition model ir packageName moduleName viewAttribute moduleDef.value
            )
        |> column []


viewModuleDefinition : Model -> IR -> PackageName -> ModuleName -> (va -> Html Msg) -> Module.Definition () (Type ()) -> Element Msg
viewModuleDefinition model ir packageName moduleName _ moduleDef =
    column []
        [ moduleDef.types
            |> viewDict
                (\typeName -> text (typeName |> Name.toHumanWords |> String.join " "))
                (\typeDef -> text (Debug.toString typeDef))
        , moduleDef.values
            |> Dict.toList
            |> List.map
                (\( valueName, valueDef ) ->
                    let
                        valueState =
                            model.valueStates
                                |> Dict.get ( packageName, moduleName, valueName )
                                |> Maybe.withDefault
                                    { typeInferenceStep = 0
                                    }
                    in
                    column
                        [ Background.color (rgb 0.9 0.9 0.9)
                        , Border.rounded 5
                        , padding 5
                        , spacing 5
                        ]
                        [ el
                            [ Border.rounded 5
                            , Background.color (rgb 0.95 0.95 0.95)
                            , width fill
                            ]
                            (row []
                                [ el [ paddingXY 10 5 ] (text (nameToText valueName))
                                , row
                                    [ paddingXY 10 5
                                    , spacing 5
                                    , Background.color (rgb 1 0.9 0.8)
                                    ]
                                    [ text ":"
                                    , XRayView.viewType pathToUrl valueDef.value.value.outputType
                                    ]
                                ]
                            )
                        , if List.isEmpty valueDef.value.value.inputTypes then
                            none

                          else
                            el
                                [ padding 5
                                , Border.rounded 5
                                , Background.color (rgb 0.95 0.95 0.95)
                                , width fill
                                ]
                                (valueDef.value.value.inputTypes
                                    |> List.map
                                        (\( argName, _, argType ) ->
                                            row []
                                                [ el [ paddingXY 10 5 ] (text (nameToText argName))
                                                , row
                                                    [ paddingXY 10 5
                                                    , spacing 5
                                                    , Background.color (rgb 1 0.9 0.8)
                                                    ]
                                                    [ text ":"
                                                    , XRayView.viewType pathToUrl argType
                                                    ]
                                                ]
                                        )
                                    |> column [ spacing 5 ]
                                )
                        , el
                            [ padding 5
                            , Border.rounded 5
                            , Background.color (rgb 1 1 1)
                            , width fill
                            ]
                            (viewValue valueState ir ( packageName, moduleName, valueName ) model.irView valueDef.value.value)
                        ]
                )
            |> column [ spacing 20 ]
        ]


viewValue : ValueState -> IR -> FQName -> IRView -> Value.Definition () (Type ()) -> Element Msg
viewValue valueState ir fullyQualifiedName irView valueDef =
    case irView of
        InsightView ->
            let
                config : Config Msg
                config =
                    { ir = ir
                    , nativeFunctions = Dict.empty
                    , state =
                        { expandedFunctions = Dict.empty
                        , variables = Dict.empty
                        , popupVariables =
                            { variableIndex = -1
                            , variableValue = Nothing
                            }
                        , theme = Theme.fromConfig Nothing
                        , highlightState = Nothing
                        }
                    , handlers =
                        { onReferenceClicked = \_ _ -> DoNothing
                        , onHoverOver = \_ _ -> DoNothing
                        , onHoverLeave = \_ -> DoNothing
                        }
                    }

                editors =
                    valueDef.inputTypes
                        |> List.map
                            (\( argName, _, argType ) ->
                                ( argName
                                , ValueEditor.view ir
                                    argType
                                    (always DoNothing)
                                    (ValueEditor.initEditorState ir argType Nothing)
                                )
                            )
                        |> FieldList.view
            in
            column []
                [ editors
                , ViewValue.viewDefinition config fullyQualifiedName valueDef
                ]

        IRView ->
            viewValueAsIR valueState ir fullyQualifiedName irView valueDef


viewValueAsIR : ValueState -> IR -> FQName -> IRView -> Value.Definition () (Type ()) -> Element Msg
viewValueAsIR valueState ir fullyQualifiedName irView valueDef =
    let
        untypedValueDef : Value.Definition () ()
        untypedValueDef =
            valueDef
                |> Value.mapDefinitionAttributes identity (always ())

        ( index, ( defVar, annotatedValueDef, valueDefConstraints ) ) =
            Infer.constrainDefinition ir Dict.empty untypedValueDef
                |> Count.apply 0

        solveSteps : List (Element msg)
        solveSteps =
            viewSolveSteps 0 ir Solve.emptySolution valueDefConstraints
                |> List.reverse

        solveStepsSlider : Element Msg
        solveStepsSlider =
            Input.slider
                [ Element.height fill
                , Element.width (Element.px 30)

                -- Here is where we're creating/styling the "track"
                , Element.behindContent
                    (Element.el
                        [ Element.height Element.fill
                        , Element.width (Element.px 2)
                        , Element.centerX
                        , Background.color (rgb 0.5 0.5 0.5)
                        , Border.rounded 2
                        ]
                        Element.none
                    )
                ]
                { onChange = round >> UpdateInferStep fullyQualifiedName
                , label =
                    Input.labelAbove []
                        (text "Infer")
                , min = 0
                , max = toFloat (List.length solveSteps - 1)
                , step = Just 1
                , value = toFloat valueState.typeInferenceStep
                , thumb =
                    Input.defaultThumb
                }

        solveStepsView =
            solveSteps
                |> List.drop valueState.typeInferenceStep
                |> List.head
                |> Maybe.map
                    (\content ->
                        el [ paddingEach { left = 20, right = 10, bottom = 0, top = 0 } ] content
                    )
                |> Maybe.withDefault none
    in
    column []
        [ row [ spacing 20 ]
            [ column [ spacing 10 ]
                [ text (String.concat [ "definition var: ", String.fromInt defVar ])
                , XRayView.viewValueDefinition
                    (\( _, metaVar ) ->
                        text (String.fromInt metaVar)
                    )
                    annotatedValueDef
                ]
            ]
        , row [ height (px 500) ]
            [ solveStepsSlider
            , solveStepsView
            ]
        ]


viewConstraints : ConstraintSet -> Element msg
viewConstraints constraints =
    table [ spacing 10 ]
        { data =
            constraints
                |> ConstraintSet.toList
        , columns =
            [ { header = none
              , width = shrink
              , view =
                    \constraint ->
                        case constraint of
                            Equality _ metaType1 _ ->
                                viewMetaType metaType1

                            Class _ metaType _ ->
                                viewMetaType metaType
              }
            , { header = none
              , width = shrink
              , view =
                    \constraint ->
                        case constraint of
                            Equality _ _ _ ->
                                text "="

                            Class _ _ _ ->
                                text "is a"
              }
            , { header = none
              , width = shrink
              , view =
                    \constraint ->
                        case constraint of
                            Equality _ _ metaType2 ->
                                viewMetaType metaType2

                            Class _ _ cls ->
                                text (Debug.toString cls)
              }
            ]
        }


viewMetaType : MetaType -> Element msg
viewMetaType metaType =
    case metaType of
        MetaVar variable ->
            text (String.fromInt variable)

        MetaRef _ ( packageName, moduleName, localName ) args maybeMetaType ->
            text (Name.toTitleCase localName)

        MetaTuple _ metaTypes ->
            text "(,)"

        MetaRecord _ var isOpen fields ->
            row []
                [ text "{ "
                , text (String.fromInt var)
                , if isOpen then
                    text " = "

                  else
                    text " | "
                , fields
                    |> Dict.toList
                    |> List.map (\( n, t ) -> row [] [ text (Name.toCamelCase n), text " : ", viewMetaType t ])
                    |> List.intersperse (text ", ")
                    |> row []
                , text " }"
                ]

        MetaFun _ metaType1 metaType2 ->
            row [] [ viewMetaType metaType1, text " -> ", viewMetaType metaType2 ]

        MetaUnit ->
            text "()"


viewSolution : SolutionMap -> Element msg
viewSolution solutionMap =
    table [ spacing 10 ]
        { data =
            solutionMap
                |> Solve.toList
        , columns =
            [ { header = none
              , width = shrink
              , view =
                    \( variable, _ ) ->
                        text (String.fromInt variable)
              }
            , { header = none
              , width = shrink
              , view =
                    \_ ->
                        text "="
              }
            , { header = none
              , width = shrink
              , view =
                    \( _, metaType ) ->
                        viewMetaType metaType
              }
            ]
        }


viewSolveSteps : Int -> IR -> SolutionMap -> ConstraintSet -> List (Element msg)
viewSolveSteps depth ir solutionMap constraintSet =
    let
        thisStep : Element msg
        thisStep =
            column [ spacing 20 ]
                [ text "Constraints"
                , viewConstraints constraintSet
                , text "Solutions"
                , viewSolution solutionMap
                ]
    in
    case Infer.solveStep ir solutionMap constraintSet of
        Ok (Just ( newConstraints, mergedSolutions )) ->
            if depth > 2000 then
                [ thisStep ]

            else
                thisStep :: viewSolveSteps (depth + 1) ir mergedSolutions newConstraints

        Ok Nothing ->
            [ thisStep ]

        Err error ->
            [ text (Debug.toString error) ]


viewFields : List ( Element msg, Element msg ) -> Element msg
viewFields fields =
    fields
        |> List.map
            (\( key, value ) ->
                column []
                    [ key
                    , el [ paddingXY 10 5 ] value
                    ]
            )
        |> column []


viewDict : (comparable -> Element msg) -> (v -> Element msg) -> Dict comparable v -> Element msg
viewDict viewKey viewVal dict =
    dict
        |> Dict.toList
        |> List.map
            (\( key, value ) ->
                column []
                    [ viewKey key
                    , el [ paddingXY 10 5 ]
                        (viewVal value)
                    ]
            )
        |> column []


viewIRViewTabs : IRView -> Element Msg
viewIRViewTabs irView =
    let
        button viewType labelText =
            Input.button
                [ paddingXY 10 5
                , Background.color
                    (if viewType == irView then
                        rgb 0.8 0.85 0.9

                     else
                        rgb 0.9 0.9 0.9
                    )
                , Border.rounded 3
                ]
                { onPress = Just (ChangeIRView viewType)
                , label = el [] (text labelText)
                }
    in
    row
        [ alignRight
        , paddingXY 10 0
        , spacing 10
        ]
        [ button InsightView "Insight"
        , button IRView "IR"
        ]


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


packageInfo =
    { name = [ [ "my" ] ]
    , exposedModules = Nothing
    }


sampleSourcePrefix : String
sampleSourcePrefix =
    """module My.Test exposing (..)
    """


sampleSource : String
sampleSource =
    """
test =
  \\rec ->
    if False then
      rec.bar
    else
      2.0
        """
