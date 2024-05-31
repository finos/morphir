module Morphir.Elm.ParsedModule exposing (..)

import Elm.Processing as Processing exposing (ProcessContext)
import Elm.RawFile as RawFile exposing (RawFile)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing exposing (Exposing)
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Module exposing (Module(..))
import Elm.Syntax.Node as Node exposing (Node)
import Morphir.Elm.ModuleName exposing (ModuleName)
import Morphir.Elm.WellKnownOperators as WellKnownOperators


type ParsedModule
    = ParsedModule File


parsedModule : RawFile -> ParsedModule
parsedModule rawFile =
    ParsedModule
        (rawFile
            |> Processing.process
                (initialContext
                    |> withWellKnownOperators
                )
        )


initialContext : ProcessContext
initialContext =
    Processing.init |> withWellKnownOperators


withWellKnownOperators : ProcessContext -> ProcessContext
withWellKnownOperators processContext =
    List.foldl Processing.addDependency processContext WellKnownOperators.wellKnownOperators


moduleName : ParsedModule -> ModuleName
moduleName (ParsedModule file) =
    case file.moduleDefinition |> Node.value of
        NormalModule defaultModuleData ->
            defaultModuleData.moduleName |> Node.value

        PortModule defaultModuleData ->
            defaultModuleData.moduleName |> Node.value

        EffectModule effectModuleData ->
            effectModuleData.moduleName |> Node.value


exposingList : ParsedModule -> Exposing
exposingList (ParsedModule file) =
    case file.moduleDefinition |> Node.value of
        NormalModule defaultModuleData ->
            defaultModuleData.exposingList |> Node.value

        PortModule defaultModuleData ->
            defaultModuleData.exposingList |> Node.value

        EffectModule effectModuleData ->
            effectModuleData.exposingList |> Node.value


imports : ParsedModule -> List Import
imports (ParsedModule file) =
    file.imports
        |> List.map Node.value


importedModules : ParsedModule -> List ModuleName
importedModules (ParsedModule file) =
    file.imports
        |> List.map (Node.value >> .moduleName >> Node.value)


declarations : ParsedModule -> List (Node Declaration)
declarations (ParsedModule file) =
    file.declarations


documentation : ParsedModule -> Maybe String
documentation (ParsedModule file) =
    if List.isEmpty file.comments then
        Nothing

    else
        file.comments
            |> List.map Node.value
            |> List.filter (String.startsWith "{-|")
            |> List.head
            |> Maybe.map (String.dropLeft 3 >> String.dropRight 3)
