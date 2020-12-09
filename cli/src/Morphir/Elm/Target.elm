module Morphir.Elm.Target exposing (..)

import Json.Decode as Decode exposing (Error, Value)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Distribution exposing (Distribution)
import Morphir.IR.Package as Package
import Morphir.Scala.Backend
import Morphir.SpringBoot.Backend as SpringBoot
import Morphir.SpringBoot.Backend.Codec
import Morphir.Graph.TriplesBackend as Triples
import Morphir.Graph.CypherBackend as Cypher
import Morphir.Graph.Backend.Codec
import Morphir.Scala.Backend.Codec

-- possible language generation options
type BackendOptions
    = ScalaOptions Morphir.Scala.Backend.Options
    | SpringBootOptions Morphir.Scala.Backend.Options
    | TriplesOptions Morphir.Scala.Backend.Options
    | CypherOptions Morphir.Scala.Backend.Options

decodeOptions : Result Error String -> Decode.Decoder BackendOptions
decodeOptions gen =
    case gen of
        Ok "SpringBoot" -> Decode.map (\(options) -> SpringBootOptions(options)) Morphir.SpringBoot.Backend.Codec.decodeOptions
        Ok "triples" -> Decode.map (\(options) -> TriplesOptions(options)) Morphir.Graph.Backend.Codec.decodeOptions
        Ok "cypher" -> Decode.map (\(options) -> CypherOptions(options)) Morphir.Graph.Backend.Codec.decodeOptions
        _ -> Decode.map (\(options) -> ScalaOptions(options)) Morphir.Scala.Backend.Codec.decodeOptions

mapDistribution : BackendOptions -> Distribution -> FileMap
mapDistribution back dist =
    case back of
            SpringBootOptions options -> SpringBoot.mapDistribution options dist
            TriplesOptions options -> Triples.mapDistribution options dist
            CypherOptions options -> Cypher.mapDistribution options dist
            ScalaOptions options -> Morphir.Scala.Backend.mapDistribution options dist
