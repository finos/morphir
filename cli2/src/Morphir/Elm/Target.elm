module Morphir.Elm.Target exposing (..)

import Json.Decode as Decode exposing (Error, Value)
import Json.Encode as Encode
import Morphir.Correctness.Test exposing (TestSuite)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.Graph.Backend.Codec
import Morphir.Graph.CypherBackend as Cypher
import Morphir.Graph.SemanticBackend as SemanticBackend
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.JsonSchema.Backend as JsonSchemaBackend
import Morphir.JsonSchema.Backend.Codec
import Morphir.Scala.Backend
import Morphir.Scala.Backend.Codec
import Morphir.Scala.Spark.Backend
import Morphir.SpringBoot.Backend as SpringBoot
import Morphir.SpringBoot.Backend.Codec
import Morphir.TypeScript.Backend
import Morphir.Snowpark.Backend



-- possible language generation options


type BackendOptions
    = ScalaOptions Morphir.Scala.Backend.Options
    | SpringBootOptions SpringBoot.Options
    | SemanticOptions Cypher.Options
    | CypherOptions Cypher.Options
    | TypeScriptOptions Morphir.TypeScript.Backend.Options
    | SparkOptions Morphir.Scala.Spark.Backend.Options
    | JsonSchemaOptions JsonSchemaBackend.Options
    | SnowparkOptions Morphir.Snowpark.Backend.Options

type alias Errors =
    List String


decodeOptions : Result Error String -> Decode.Decoder BackendOptions
decodeOptions gen =
    case gen of
        Ok "SpringBoot" ->
            Decode.map (\options -> SpringBootOptions options) Morphir.SpringBoot.Backend.Codec.decodeOptions

        Ok "semantic" ->
            Decode.map (\options -> SemanticOptions options) Morphir.Graph.Backend.Codec.decodeOptions

        Ok "cypher" ->
            Decode.map (\options -> CypherOptions options) Morphir.Graph.Backend.Codec.decodeOptions

        Ok "TypeScript" ->
            Decode.map (\options -> TypeScriptOptions options) Morphir.Graph.Backend.Codec.decodeOptions

        Ok "Spark" ->
            Decode.map SparkOptions (Decode.succeed Morphir.Scala.Spark.Backend.Options)

        Ok "Snowpark" ->
            Decode.map SnowparkOptions Morphir.Snowpark.Backend.decodeOptions

        Ok "JsonSchema" ->
            Decode.map (\options -> JsonSchemaOptions options) Morphir.JsonSchema.Backend.Codec.decodeOptions

        _ ->
            Decode.map (\options -> ScalaOptions options) Morphir.Scala.Backend.Codec.decodeOptions


mapDistribution : BackendOptions -> TestSuite -> Distribution -> Result Encode.Value FileMap
mapDistribution backendOptions morphirTestSuite dist =
    case backendOptions of
        SpringBootOptions options ->
            Ok <| SpringBoot.mapDistribution options dist

        SemanticOptions options ->
            Ok <| SemanticBackend.mapDistribution options dist

        CypherOptions options ->
            Ok <| Cypher.mapDistribution options dist

        ScalaOptions options ->
            Morphir.Scala.Backend.mapDistribution options morphirTestSuite dist
                |> Result.mapError Morphir.Scala.Backend.Codec.encodeError

        TypeScriptOptions options ->
            Ok <| Morphir.TypeScript.Backend.mapDistribution options dist

        SparkOptions options ->
            Ok <| Morphir.Scala.Spark.Backend.mapDistribution options dist

        SnowparkOptions options ->
            Ok <| Morphir.Snowpark.Backend.mapDistribution options dist

        JsonSchemaOptions options ->
            JsonSchemaBackend.mapDistribution options dist
                |> Result.mapError Morphir.JsonSchema.Backend.Codec.encodeErrors
