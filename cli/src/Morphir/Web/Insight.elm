port module Morphir.Web.Insight exposing (Model, Msg(..), init, main, receiveFunctionArguments, receiveFunctionName, subscriptions, update, view)

import Browser
import Dict exposing (Dict)
import Element exposing (padding, spacing)
import Element.Font as Font
import Html exposing (Html)
import Json.Decode as Decode exposing (Decoder, string)
import Morphir.Compiler.Codec as CompilerCodec
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.QName as QName exposing (QName(..))
import Morphir.IR.Value exposing (Value)
import Morphir.IR.Value.Codec as ValueCodec
import Morphir.Value.Interpreter as Interpreter
import Morphir.Visual.Components.Theme exposing (Style, Theme, scaled)
import Morphir.Visual.Components.VisualizationState exposing (VisualizationState)
import Morphir.Visual.Config exposing (Config)
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


type alias Flags =
    { distribution : Decode.Value
    , style : Style
    }


type alias Model =
    { theme : Theme
    , modelState : ModelState
    }


type ModelState
    = IRLoaded Distribution
    | FunctionsSet VisualizationState
    | Failed String


init : Flags -> ( Model, Cmd Msg )
init flags =
    let
        styleTheme : Theme
        styleTheme =
            { fontSize = flags.style.fontSize
            , smallSpacing = scaled -3 flags.style
            , mediumSpacing = scaled 1 flags.style
            , largeSpacing = scaled 6 flags.style
            , smallPadding = scaled -4 flags.style
            , mediumPadding = scaled -2 flags.style
            , largePadding = scaled 2 flags.style
            }

        model =
            case flags.distribution |> Decode.decodeValue CompilerCodec.decodeIR of
                Ok distribution ->
                    { theme = styleTheme, modelState = IRLoaded distribution }

                Err error ->
                    { theme = styleTheme, modelState = Failed ("Wrong IR: " ++ Decode.errorToString error) }
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
                jsonDecoder =
                    Decode.list (ValueCodec.decodeValue (Decode.succeed ()) (Decode.succeed ()))
            in
            case jsonList |> Decode.decodeValue jsonDecoder of
                Ok updatedArgValues ->
                    case model.modelState of
                        FunctionsSet visualizationState ->
                            ( { model | modelState = FunctionsSet { visualizationState | functionArguments = updatedArgValues } }
                            , Cmd.none
                            )

                        _ ->
                            ( { model | modelState = Failed "Invalid State" }, Cmd.none )

                Err _ ->
                    ( { model | modelState = Failed "Received function arguments cannot be decoded" }, Cmd.none )

        ExpandReference (( packageName, moduleName, localName ) as fqName) bool ->
            case model.modelState of
                FunctionsSet visualizationState ->
                    if visualizationState.expandedFunctions |> Dict.member fqName then
                        case bool of
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
            Element.layout [ Font.size model.theme.fontSize, padding model.theme.mediumPadding, Font.bold ] (Element.text string)

        FunctionsSet visualizationState ->
            let
                validArgValues : Dict Name (Value () ())
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
                        , theme = model.theme
                        }
                    , handlers =
                        { onReferenceClicked = ExpandReference
                        }
                    }

                valueFQName : FQName
                valueFQName =
                    case ( visualizationState.distribution, visualizationState.selectedFunction ) of
                        ( Library packageName _ _, QName moduleName localName ) ->
                            ( packageName, moduleName, localName )
            in
            ViewValue.viewDefinition config valueFQName visualizationState.functionDefinition
                |> Element.layout [ Font.size model.theme.fontSize, padding model.theme.mediumPadding, spacing model.theme.mediumSpacing ]
