module Morphir.Elm.Target exposing (..)

import Dict
import Json.Decode as Decode exposing (Error, Value)
import Json.Encode as Encode
import Morphir.File.FileMap exposing (FileMap)
import Morphir.Graph.Backend.Codec
import Morphir.Graph.CypherBackend as Cypher
import Morphir.Graph.SemanticBackend as SemanticBackend
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.JsonSchema.Backend exposing (Errors)
import Morphir.JsonSchema.Backend.Codec
import Morphir.Scala.Backend
import Morphir.Scala.Backend.Codec
import Morphir.Scala.Spark.Backend
import Morphir.Spark.Backend
import Morphir.SpringBoot.Backend as SpringBoot
import Morphir.SpringBoot.Backend.Codec
import Morphir.TypeScript.Backend
import Morphir.TypeSpec.Backend
import Morphir.TypeSpec.Backend.Codec
import Morphir.Snowpark.Backend



-- possible language generation options


type BackendOptions
    = ScalaOptions Morphir.Scala.Backend.Options
    | SpringBootOptions SpringBoot.Options
    | SemanticOptions Cypher.Options
    | CypherOptions Cypher.Options
    | TypeScriptOptions Morphir.TypeScript.Backend.Options
    | SparkOptions Morphir.Scala.Spark.Backend.Options
    | JsonSchemaOptions Morphir.JsonSchema.Backend.Options
    | TypeSpecOptions Morphir.TypeSpec.Backend.Options
    | SnowparkOptions Morphir.Snowpark.Backend.Options


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
            Decode.map JsonSchemaOptions Morphir.JsonSchema.Backend.Codec.decodeOptions

        Ok "TypeSpec" ->
            Decode.map TypeSpecOptions (Decode.succeed Morphir.TypeSpec.Backend.Options)

        _ ->
            Decode.map (\options -> ScalaOptions options) Morphir.Scala.Backend.Codec.decodeOptions


mapDistribution : BackendOptions -> Distribution -> Result Encode.Value FileMap
mapDistribution back dist =
    case back of
        SpringBootOptions options ->
            Ok <| SpringBoot.mapDistribution options dist

        SemanticOptions options ->
            Ok <| SemanticBackend.mapDistribution options dist

        CypherOptions options ->
            Ok <| Cypher.mapDistribution options dist

        ScalaOptions options ->
            Morphir.Scala.Backend.mapDistribution options Dict.empty dist
                |> Result.mapError Morphir.Scala.Backend.Codec.encodeError

        TypeScriptOptions options ->
            Ok <| Morphir.TypeScript.Backend.mapDistribution options dist

        SparkOptions options ->
            Ok <| Morphir.Spark.Backend.mapDistribution options dist
        
        SnowparkOptions options ->
            Ok <| Morphir.Snowpark.Backend.mapDistribution options dist

        JsonSchemaOptions options ->
            Morphir.JsonSchema.Backend.mapDistribution options dist
                |> Result.mapError Morphir.JsonSchema.Backend.Codec.encodeErrors

        TypeSpecOptions options ->
            Morphir.TypeSpec.Backend.mapDistribution options dist
                |> Result.mapError Morphir.TypeSpec.Backend.Codec.encodeErrors
