module Morphir.Elm.ParsedModule exposing (..)

import Elm.RawFile as RawFile exposing (RawFile)
import Elm.Syntax.Node as Node
import Morphir.Elm.ModuleName exposing (ModuleName)


type alias ParsedModule =
    RawFile


moduleName : ParsedModule -> ModuleName
moduleName =
    RawFile.moduleName


importedModules : ParsedModule -> List ModuleName
importedModules parsedModule =
    parsedModule
        |> RawFile.imports
        |> List.map (.moduleName >> Node.value)
