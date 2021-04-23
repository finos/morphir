port module Morphir.Web.Insight exposing (Model, Msg(..), init, main, receiveFunctionArguments, receiveFunctionName, subscriptions, update, view)

import Browser
import Dict exposing (Dict)
import Element exposing (padding, spacing)
import Element.Font as Font
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder, string)
import Morphir.IR as IR exposing (IR, fromDistribution)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Distribution.Codec as DistributionCodec
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.QName as QName exposing (QName(..))
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.DataCodec exposing (decodeData)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Value.Interpreter as Interpreter
import Morphir.Visual.Components.VisualizationState exposing (VisualizationState)
import Morphir.Visual.Config exposing (Config, PopupScreenRecord)
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
                    { theme = Theme.fromConfig flag.config, modelState = IRLoaded flag.distribution }

                Err error ->
                    { theme = Theme.fromConfig Nothing, modelState = Failed ("Wrong IR: " ++ Decode.errorToString error) }
    in
    ( model, Cmd.none )



-- PORTS


port receiveFunctionName : (String -> msg) -> Sub msg


port receiveFunctionArguments : (Decode.Value -> msg) -> Sub msg



-- UPDATE


type Msg
    = FunctionNameReceived String
    | FunctionArgumentsReceived Decode.Value
    | ExpandReference FQName Bool
    | ExpandVariable Int (Maybe RawValue)
    | ShrinkVariable Int


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
                    }
            in
            case qNameString |> QName.fromString of
                Just qName ->
                    getDistribution
                        |> Maybe.andThen
                            (\distribution ->
                                distribution
                                    |> Distribution.lookupValueDefinition qName
                                    |> Maybe.map
                                        (\funDef ->
                                            { model
                                                | modelState =
                                                    FunctionsSet
                                                        { distribution = distribution
                                                        , selectedFunction = qName
                                                        , functionDefinition = funDef
                                                        , functionArguments = []
                                                        , expandedFunctions = Dict.empty
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
                getIR : IR
                getIR =
                    case getDistribution of
                        Just distribution ->
                            fromDistribution distribution

                        Nothing ->
                            IR.empty

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

        ExpandReference (( packageName, moduleName, localName ) as fqName) isFunctionPresent ->
            case model.modelState of
                FunctionsSet visualizationState ->
                    if visualizationState.expandedFunctions |> Dict.member fqName then
                        case isFunctionPresent of
                            True ->
                                ( { model | modelState = FunctionsSet { visualizationState | expandedFunctions = visualizationState.expandedFunctions |> Dict.remove fqName } }, Cmd.none )

                            False ->
                                ( model, Cmd.none )

                    else
                        ( { model
                            | modelState =
                                FunctionsSet
                                    { visualizationState
                                        | expandedFunctions =
                                            Distribution.lookupValueDefinition (QName moduleName localName) visualizationState.distribution
                                                |> Maybe.map (\valueDef -> visualizationState.expandedFunctions |> Dict.insert fqName valueDef)
                                                |> Maybe.withDefault visualizationState.expandedFunctions
                                    }
                          }
                        , Cmd.none
                        )

                _ ->
                    ( model, Cmd.none )

        ExpandVariable varIndex maybeRawValue ->
            case model.modelState of
                FunctionsSet visualizationState ->
                    let
                        popupScreen : PopupScreenRecord
                        popupScreen =
                            { variableIndex = varIndex
                            , variableValue = maybeRawValue
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

        ShrinkVariable varIndex ->
            case model.modelState of
                FunctionsSet visualizationState ->
                    let
                        popupScreen : PopupScreenRecord
                        popupScreen =
                            { variableIndex = varIndex
                            , variableValue = Nothing
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
                    { irContext =
                        { distribution = visualizationState.distribution
                        , references = Interpreter.referencesForDistribution visualizationState.distribution
                        }
                    , state =
                        { expandedFunctions = visualizationState.expandedFunctions
                        , variables = validArgValues
                        , popupVariables = visualizationState.popupVariables
                        , theme = model.theme
                        }
                    , handlers =
                        { onReferenceClicked = ExpandReference
                        , onHoverOver = ExpandVariable
                        , onHoverLeave = ShrinkVariable
                        }
                    }

                valueFQName : FQName
                valueFQName =
                    case ( visualizationState.distribution, visualizationState.selectedFunction ) of
                        ( Library packageName _ _, QName moduleName localName ) ->
                            ( packageName, moduleName, localName )
            in
            ViewValue.viewDefinition config valueFQName visualizationState.functionDefinition
                |> Element.layout [ Font.size model.theme.fontSize, smallPadding model.theme |> padding, smallSpacing model.theme |> spacing ]


decodeFlag : Decode.Decoder Flag
decodeFlag =
    Decode.map2 Flag
        (Decode.field "distribution" DistributionCodec.decodeVersionedDistribution)
        (Decode.field "config" decodeThemeConfig |> Decode.maybe)
