module Morphir.Elm.ParsedModule exposing (..)

import Elm.Processing as Processing exposing (ProcessContext)
import Elm.RawFile as RawFile exposing (RawFile)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Node as Node exposing (Node)
import Morphir.Elm.ModuleName exposing (ModuleName)
import Morphir.Elm.WellKnownOperators as WellKnownOperators


type alias ParsedModule =
    RawFile


initialContext : ProcessContext
initialContext =
    Processing.init |> withWellKnownOperators


withWellKnownOperators : ProcessContext -> ProcessContext
withWellKnownOperators processContext =
    List.foldl Processing.addDependency processContext WellKnownOperators.wellKnownOperators


moduleName : ParsedModule -> ModuleName
moduleName =
    RawFile.moduleName


importedModules : ParsedModule -> List ModuleName
importedModules parsedModule =
    parsedModule
        |> RawFile.imports
        |> List.map (.moduleName >> Node.value)


declarations : ParsedModule -> List (Node Declaration)
declarations parsedModule =
    parsedModule
        |> Processing.process initialContext
        |> (\file ->
                file.declarations
           )


typeDeclarations : ParsedModule -> List Declaration
typeDeclarations parsedModule =
    parsedModule
        |> declarations
        |> List.filterMap
            (\dec ->
                case Node.value dec of
                    CustomTypeDeclaration typ ->
                        Just (CustomTypeDeclaration typ)

                    AliasDeclaration typAlias ->
                        Just (AliasDeclaration typAlias)

                    _ ->
                        Nothing
            )
