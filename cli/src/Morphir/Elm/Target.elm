module Morphir.Elm.Target exposing (..)

import Json.Decode as Decode exposing (Error, Value)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Package as Package
import Morphir.Scala.Backend
import Morphir.SpringBoot.Backend as SpringBoot
import Morphir.SpringBoot.Backend.Codec
import Morphir.Scala.Backend.Codec

-- possible language generation options
type BackendOptions
    = ScalaOptions Morphir.Scala.Backend.Options
    | SpringBootOptions Morphir.Scala.Backend.Options

decodeOptions : Result Error String -> Decode.Decoder BackendOptions
decodeOptions gen =
    case gen of
        Ok "SpringBoot" -> Decode.map (\(options) -> SpringBootOptions(options)) Morphir.SpringBoot.Backend.Codec.decodeOptions
        _ -> Decode.map (\(options) -> ScalaOptions(options)) Morphir.Scala.Backend.Codec.decodeOptions

mapDistribution : BackendOptions -> Package.Distribution -> FileMap
mapDistribution back =
    case back of
            SpringBootOptions options -> SpringBoot.mapDistribution options
            ScalaOptions options -> Morphir.Scala.Backend.mapDistribution options
