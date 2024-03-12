port module Morphir.Web.Insight exposing (Model, Msg(..), init, main, receiveFunctionArguments, receiveFunctionName, subscriptions, update, view)

import Browser
import Dict exposing (Dict)
import Element exposing (padding, spacing)
import Element.Font as Font
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder, string)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.FormatVersion.Codec as DistributionCodec
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.QName as QName exposing (QName(..))
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.DataCodec exposing (decodeData)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Visual.Components.VisualizationState exposing (VisualizationState)
import Morphir.Visual.Config as Config exposing (Config, DrillDownFunctions(..), ExpressionTreePath, PopupScreenRecord, addToDrillDown, removeFromDrillDown)
import Morphir.Visual.Theme as Theme exposing (Theme, ThemeConfig, smallPadding, smallSpacing)
import Morphir.Visual.Theme.Codec exposing (decodeThemeConfig)
import Morphir.Visual.ViewValue as ViewValue



-- MAIN


main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- MODEL


type alias Flag =
    { distribution : Distribution
    , config : Maybe ThemeConfig
    }


type alias Model =
    { theme : Theme
    , modelState : ModelState
    , ir : Maybe Distribution
    }


type ModelState
    = IRLoaded Distribution
    | FunctionsSet VisualizationState
    | Failed String


init : Decode.Value -> ( Model, Cmd Msg )
init json =
    let
        model =
            case json |> Decode.decodeValue decodeFlag of
                Ok flag ->
                    { theme = Theme.fromConfig flag.config, modelState = IRLoaded flag.distribution, ir = Just flag.distribution }

                Err error ->
                    { theme = Theme.fromConfig Nothing, modelState = Failed ("Wrong IR: " ++ Decode.errorToString error), ir = Nothing }
    in
    ( model, Cmd.none )



-- PORTS


port receiveFunctionName : (String -> msg) -> Sub msg


port receiveFunctionArguments : (Decode.Value -> msg) -> Sub msg



-- UPDATE


type Msg
    = FunctionNameReceived String
    | FunctionArgumentsReceived Decode.Value
    | ExpandReference FQName Int ExpressionTreePath
    | ShrinkReference FQName Int ExpressionTreePath
    | ExpandVariable Int (List Int) (Maybe RawValue)
    | ShrinkVariable Int (List Int)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    let
        getDistribution : Maybe Distribution
        getDistribution =
            case model.modelState of
                IRLoaded distribution ->
                    Just distribution

                FunctionsSet visualizationState ->
                    Just visualizationState.distribution

                _ ->
                    Nothing
    in
    case msg of
        FunctionNameReceived qNameString ->
            let
                popupScreen : PopupScreenRecord
                popupScreen =
                    { variableIndex = 0
                    , variableValue = Nothing
                    , nodePath = []
                    }
            in
            case qNameString |> QName.fromString of
                Just qName ->
                    getDistribution
                        |> Maybe.andThen
                            (\distribution ->
                                let
                                    fQName : FQName
                                    fQName =
                                        ( getPackageName distribution, QName.getModulePath qName, QName.getLocalName qName )
                                in
                                distribution
                                    |> Distribution.lookupValueDefinition fQName
                                    |> Maybe.map
                                        (\funDef ->
                                            { model
                                                | modelState =
                                                    FunctionsSet
                                                        { distribution = distribution
                                                        , selectedFunction = qName
                                                        , functionDefinition = funDef
                                                        , functionArguments = []
                                                        , drillDownFunctions = DrillDownFunctions Dict.empty
                                                        , popupVariables = popupScreen
                                                        }
                                            }
                                        )
                            )
                        |> Maybe.map (\m -> ( m, Cmd.none ))
                        |> Maybe.withDefault ( { model | modelState = Failed "Invalid State in receiving function name" }, Cmd.none )

                Nothing ->
                    ( { model | modelState = Failed "Received function name is not found" }, Cmd.none )

        FunctionArgumentsReceived jsonList ->
            let
                getIR : Distribution
                getIR =
                    case getDistribution of
                        Just distribution ->
                            distribution

                        Nothing ->
                            -- empty distribution
                            Library [ [ "empty" ] ] Dict.empty Package.emptyDefinition

                getTypes : Type ()
                getTypes =
                    case model.modelState of
                        FunctionsSet visualizationState ->
                            List.map (\( name, _, tpe ) -> tpe) visualizationState.functionDefinition.inputTypes |> Type.Tuple ()

                        _ ->
                            Type.Unit ()

                jsonDecoder : Result String (Decoder RawValue)
                jsonDecoder =
                    decodeData getIR getTypes
            in
            case jsonDecoder |> Result.andThen (\decoder -> jsonList |> Decode.decodeValue decoder |> Result.mapError Decode.errorToString) of
                Ok tupleList ->
                    let
                        updatedArgValues =
                            case tupleList of
                                Value.Tuple _ list ->
                                    list

                                _ ->
                                    []
                    in
                    case model.modelState of
                        FunctionsSet visualizationState ->
                            ( { model | modelState = FunctionsSet { visualizationState | functionArguments = updatedArgValues } }
                            , Cmd.none
                            )

                        _ ->
                            ( { model | modelState = Failed "Invalid State" }, Cmd.none )

                Err _ ->
                    ( { model | modelState = Failed "Received function arguments cannot be decoded" }, Cmd.none )

        ExpandReference fQName id nodePath ->
            case model.modelState of
                FunctionsSet visualizationState ->
                    case ( fQName, id, nodePath ) of
                        ( ( [ [ "morphir" ], [ "s", "d", "k" ] ], _, _ ), _, _ ) ->
                            ( model, Cmd.none )

                        _ ->
                            ( { model
                                | modelState =
                                    FunctionsSet
                                        { visualizationState
                                            | drillDownFunctions = DrillDownFunctions (addToDrillDown visualizationState.drillDownFunctions id nodePath)
                                        }
                              }
                            , Cmd.none
                            )

                _ ->
                    ( model, Cmd.none )

        ShrinkReference fQName id nodePath ->
            case model.modelState of
                FunctionsSet visualizationState ->
                    case ( fQName, id, nodePath ) of
                        ( ( [ [ "morphir" ], [ "s", "d", "k" ] ], _, _ ), _, _ ) ->
                            ( model, Cmd.none )

                        _ ->
                            ( { model
                                | modelState =
                                    FunctionsSet
                                        { visualizationState
                                            | drillDownFunctions = DrillDownFunctions (removeFromDrillDown visualizationState.drillDownFunctions id nodePath)
                                        }
                              }
                            , Cmd.none
                            )

                _ ->
                    ( model, Cmd.none )

        ExpandVariable varIndex nodePath maybeRawValue ->
            case model.modelState of
                FunctionsSet visualizationState ->
                    let
                        popupScreen : PopupScreenRecord
                        popupScreen =
                            { variableIndex = varIndex
                            , variableValue = maybeRawValue
                            , nodePath = nodePath
                            }
                    in
                    ( { model
                        | modelState =
                            FunctionsSet
                                { visualizationState
                                    | popupVariables = popupScreen
                                }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ShrinkVariable varIndex nodePath ->
            case model.modelState of
                FunctionsSet visualizationState ->
                    let
                        popupScreen : PopupScreenRecord
                        popupScreen =
                            { variableIndex = varIndex
                            , variableValue = Nothing
                            , nodePath = nodePath
                            }
                    in
                    ( { model
                        | modelState =
                            FunctionsSet
                                { visualizationState
                                    | popupVariables = popupScreen
                                }
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch [ receiveFunctionArguments FunctionArgumentsReceived, receiveFunctionName FunctionNameReceived ]



-- VIEW


view : Model -> Html Msg
view model =
    case model.modelState of
        IRLoaded _ ->
            Html.div [] []

        Failed string ->
            Element.layout [ Font.size model.theme.fontSize, smallPadding model.theme |> padding, Font.bold ] (Element.text string)

        FunctionsSet visualizationState ->
            let
                validArgValues : Dict Name RawValue
                validArgValues =
                    List.map2
                        (\( argName, _, _ ) argValue ->
                            ( argName, argValue )
                        )
                        visualizationState.functionDefinition.inputTypes
                        visualizationState.functionArguments
                        |> Dict.fromList

                config : Config Msg
                config =
                    Config.fromIR visualizationState.distribution
                        { drillDownFunctions = visualizationState.drillDownFunctions
                        , variables = validArgValues
                        , popupVariables = visualizationState.popupVariables
                        , theme = model.theme
                        , highlightState = Nothing
                        , nonEvaluatedVariables = Dict.empty
                        , zIndex = 9999
                        }
                        { onReferenceClicked = ExpandReference
                        , onReferenceClose = ShrinkReference
                        , onHoverOver = ExpandVariable
                        , onHoverLeave = ShrinkVariable
                        }

                valueFQName : FQName
                valueFQName =
                    case ( visualizationState.distribution, visualizationState.selectedFunction ) of
                        ( Library packageName _ _, QName moduleName localName ) ->
                            ( packageName, moduleName, localName )
            in
            case model.ir of
                Just ir ->
                    ViewValue.viewDefinition config valueFQName visualizationState.functionDefinition
                        |> Element.layout [ Font.size model.theme.fontSize, smallPadding model.theme |> padding, smallSpacing model.theme |> spacing ]

                Nothing ->
                    Html.div [] []


decodeFlag : Decode.Decoder Flag
decodeFlag =
    Decode.map2 Flag
        (Decode.field "distribution" DistributionCodec.decodeVersionedDistribution)
        (Decode.field "config" decodeThemeConfig |> Decode.maybe)


getPackageName : Distribution -> PackageName
getPackageName (Library packageName _ _) =
    packageName
