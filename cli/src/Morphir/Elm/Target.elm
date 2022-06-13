module Morphir.Elm.Target exposing (..)

import Json.Decode as Decode exposing (Error, Value)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.Graph.Backend.Codec
import Morphir.Graph.CypherBackend as Cypher
import Morphir.Graph.SemanticBackend as SemanticBackend
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.Scala.Backend
import Morphir.Scala.Backend.Codec
import Morphir.Scala.Spark.Backend
import Morphir.Spark.Backend
import Morphir.SpringBoot.Backend as SpringBoot
import Morphir.SpringBoot.Backend.Codec
import Morphir.TypeScript.Backend



-- possible language generation options


type BackendOptions
    = ScalaOptions Morphir.Scala.Backend.Options
    | SpringBootOptions SpringBoot.Options
    | SemanticOptions Cypher.Options
    | CypherOptions Cypher.Options
    | TypeScriptOptions Morphir.TypeScript.Backend.Options
    | SparkOptions Morphir.Scala.Spark.Backend.Options


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

        _ ->
            Decode.map (\options -> ScalaOptions options) Morphir.Scala.Backend.Codec.decodeOptions


mapDistribution : BackendOptions -> Distribution -> FileMap
mapDistribution back dist =
    case back of
        SpringBootOptions options ->
            SpringBoot.mapDistribution options dist

        SemanticOptions options ->
            SemanticBackend.mapDistribution options dist

        CypherOptions options ->
            Cypher.mapDistribution options dist

        ScalaOptions options ->
            Morphir.Scala.Backend.mapDistribution options dist

        TypeScriptOptions options ->
            Morphir.TypeScript.Backend.mapDistribution options dist

        SparkOptions options ->
            Morphir.Spark.Backend.mapDistribution options dist
