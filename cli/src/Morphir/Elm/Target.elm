module Morphir.Elm.Target exposing (..)

import Json.Decode as Decode exposing (Error, Value)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Package as Package
import Morphir.Scala.Backend
import Morphir.SpringBoot.Backend
import Morphir.SpringBoot.Backend.Codec
import Morphir.Scala.Backend.Codec

-- languages that could be generated
type Generator
    = Scala
    | SpringBoot

type BackendOptions
    = ScalaOptions Morphir.Scala.Backend.Options
    | SpringBootOptions Morphir.SpringBoot.Backend.Options

targetLanguage: Result Error String -> Generator
targetLanguage s =
    case s of
        Ok "SpringBoot" -> SpringBoot
        _ -> Scala

decodeOptions : Generator -> Decode.Decoder BackendOptions
decodeOptions gen =
    case gen of
        SpringBoot -> Decode.map (\(options) -> SpringBootOptions(options)) Morphir.SpringBoot.Backend.Codec.decodeOptions
        _ -> Decode.map (\(options) -> ScalaOptions(options)) Morphir.Scala.Backend.Codec.decodeOptions

mapPackageDefinition : BackendOptions -> Package.PackagePath -> Package.Definition a -> FileMap
mapPackageDefinition back =
    case back of
            SpringBootOptions options -> Morphir.SpringBoot.Backend.mapPackageDefinition options
            ScalaOptions options -> Morphir.Scala.Backend.mapPackageDefinition options
