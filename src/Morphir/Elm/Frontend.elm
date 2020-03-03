module Morphir.Elm.Frontend exposing (Error(..), initFromSource)

import Dict exposing (Dict)
import Elm.Parser
import Elm.Processing as Processing
import Elm.RawFile as RawFile exposing (RawFile)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Module as ElmModule
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.TypeAnnotation as TypeAnnotation exposing (TypeAnnotation(..))
import Morphir.DAG as DAG exposing (DAG)
import Morphir.Elm.Frontend.Resolve as Resolve exposing (ModuleResolver, PackageResolver)
import Morphir.IR.AccessControl exposing (AccessControlled, private, public)
import Morphir.IR.Advanced.Module as Module
import Morphir.IR.Advanced.Package as Package
import Morphir.IR.Advanced.Type as Type exposing (Type)
import Morphir.IR.Advanced.Value as Value exposing (Value)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.ResultList as ResultList
import Parser
import Set


type alias PackageInfo =
    {}


type alias SourceFile =
    { path : String
    , content : String
    }


type alias ParsedFile =
    { sourceFile : SourceFile
    , rawFile : RawFile
    }


type alias ProcessedFile =
    { parsedFile : ParsedFile
    , file : File
    }


type alias SourceLocation =
    { source : SourceFile
    , range : ContentRange
    }


type alias ContentRange =
    { start : ContentLocation
    , end : ContentLocation
    }


type alias ContentLocation =
    { row : Int
    , column : Int
    }


type alias Errors =
    List Error


type Error
    = ParseError String (List Parser.DeadEnd)
    | CyclicModules (DAG (List String))
    | ResolveError Resolve.Error


type alias Imports =
    { lookupByExposedCtor : String -> Maybe Import
    , byModuleName : Dict ModuleName Import
    }


type alias Import =
    { packagePath : Path
    , modulePath : Path
    , exposesCtor : String -> Bool
    }


initFromSource : PackageInfo -> List SourceFile -> Result Errors (Package.Definition SourceLocation)
initFromSource packageInfo sourceFiles =
    let
        parseSources : List SourceFile -> Result Errors (List ( ModuleName, ParsedFile ))
        parseSources sources =
            sources
                |> List.map
                    (\sourceFile ->
                        Elm.Parser.parse sourceFile.content
                            |> Result.map
                                (\rawFile ->
                                    ( rawFile |> RawFile.moduleName
                                    , ParsedFile sourceFile rawFile
                                    )
                                )
                            |> Result.mapError (ParseError sourceFile.path)
                    )
                |> ResultList.toResult

        sortModules : List ( ModuleName, ParsedFile ) -> Result Errors (List ModuleName)
        sortModules modules =
            let
                ( sortedModules, cycles ) =
                    modules
                        |> List.map
                            (\( moduleName, parsedFile ) ->
                                ( moduleName
                                , parsedFile.rawFile
                                    |> RawFile.imports
                                    |> List.map (.moduleName >> Node.value)
                                    |> Set.fromList
                                )
                            )
                        |> Dict.fromList
                        |> DAG.fromDict
                        |> DAG.topologicalSort
            in
            if DAG.isEmpty cycles then
                Ok sortedModules

            else
                Err [ CyclicModules cycles ]
    in
    parseSources sourceFiles
        |> Result.andThen
            (\parsedFiles ->
                let
                    parsedFilesByModuleName =
                        parsedFiles
                            |> Dict.fromList
                in
                sortModules parsedFiles
                    |> Result.andThen (mapParsedFiles parsedFilesByModuleName)
            )
        |> Result.map
            (\moduleDefs ->
                { dependencies = Dict.empty
                , modules =
                    moduleDefs
                        |> Dict.map
                            (\_ m ->
                                public m
                             -- TODO: only expose specific modules
                            )
                }
            )


mapParsedFiles : Dict ModuleName ParsedFile -> List ModuleName -> Result Errors (Dict Path (Module.Definition SourceLocation))
mapParsedFiles parsedModules sortedModuleNames =
    sortedModuleNames
        |> List.filterMap
            (\moduleName ->
                parsedModules
                    |> Dict.get moduleName
            )
        |> List.map
            (\parsedFile ->
                parsedFile.rawFile
                    |> Processing.process Processing.init
                    |> ProcessedFile parsedFile
            )
        |> List.foldl
            (\processedFile moduleResultsSoFar ->
                moduleResultsSoFar
                    |> Result.andThen
                        (\modulesSoFar ->
                            mapProcessedFile processedFile modulesSoFar
                        )
            )
            (Ok Dict.empty)


mapProcessedFile : ProcessedFile -> Dict Path (Module.Definition SourceLocation) -> Result Errors (Dict Path (Module.Definition SourceLocation))
mapProcessedFile processedFile modulesSoFar =
    let
        modulePath =
            processedFile.file.moduleDefinition
                |> Node.value
                |> ElmModule.moduleName
                |> List.map Name.fromString
                |> Path.fromList

        moduleExpose =
            processedFile.file.moduleDefinition
                |> Node.value
                |> ElmModule.exposingList

        moduleResolver =
            Debug.todo "implement"

        typesResult : Result Errors (Dict Name (AccessControlled (Type.Definition SourceLocation)))
        typesResult =
            mapDeclarationsToType moduleResolver processedFile.parsedFile.sourceFile moduleExpose (processedFile.file.declarations |> List.map Node.value)
                |> Result.map Dict.fromList

        valuesResult : Result Errors (Dict Name (AccessControlled (Value.Definition SourceLocation)))
        valuesResult =
            Debug.todo "implement"
    in
    Result.map2
        (\types values ->
            modulesSoFar
                |> Dict.insert modulePath (Module.Definition types values)
        )
        typesResult
        valuesResult


mapDeclarationsToType : ModuleResolver -> SourceFile -> Exposing -> List Declaration -> Result Errors (List ( Name, AccessControlled (Type.Definition SourceLocation) ))
mapDeclarationsToType moduleResolver sourceFile expose decls =
    decls
        |> List.filterMap
            (\decl ->
                case decl of
                    AliasDeclaration typeAlias ->
                        mapTypeAnnotation moduleResolver sourceFile typeAlias.typeAnnotation
                            |> Result.map
                                (\typeExp ->
                                    let
                                        isExposed =
                                            case expose of
                                                Exposing.All _ ->
                                                    True

                                                Exposing.Explicit exposeList ->
                                                    exposeList
                                                        |> List.map Node.value
                                                        |> List.any
                                                            (\topLevelExpose ->
                                                                case topLevelExpose of
                                                                    Exposing.TypeOrAliasExpose exposedName ->
                                                                        exposedName == Node.value typeAlias.name

                                                                    _ ->
                                                                        False
                                                            )

                                        name =
                                            typeAlias.name
                                                |> Node.value
                                                |> Name.fromString

                                        typeParams =
                                            typeAlias.generics
                                                |> List.map (Node.value >> Name.fromString)
                                    in
                                    ( name, withAccessControl isExposed (Type.typeAliasDefinition typeParams typeExp) )
                                )
                            |> Just

                    _ ->
                        Nothing
            )
        |> ResultList.toResult
        |> Result.mapError List.concat


mapTypeAnnotation : ModuleResolver -> SourceFile -> Node TypeAnnotation -> Result Errors (Type SourceLocation)
mapTypeAnnotation moduleResolver sourceFile (Node range typeAnnotation) =
    let
        sourceLocation =
            range |> SourceLocation sourceFile
    in
    case typeAnnotation of
        GenericType varName ->
            Ok (Type.variable (varName |> Name.fromString) sourceLocation)

        Typed (Node _ ( moduleName, localName )) argNodes ->
            Result.map2
                (\resolvedName args ->
                    Type.reference resolvedName args sourceLocation
                )
                (moduleResolver.resolveType moduleName localName
                    |> Result.mapError (ResolveError >> List.singleton)
                )
                (argNodes
                    |> List.map (mapTypeAnnotation moduleResolver sourceFile)
                    |> ResultList.toResult
                    |> Result.mapError List.concat
                )

        Unit ->
            Ok (Type.unit sourceLocation)

        Tupled elemNodes ->
            elemNodes
                |> List.map (mapTypeAnnotation moduleResolver sourceFile)
                |> ResultList.toResult
                |> Result.map (\elemTypes -> Type.tuple elemTypes sourceLocation)
                |> Result.mapError List.concat

        Record fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldTypeNode ) ->
                        mapTypeAnnotation moduleResolver sourceFile fieldTypeNode
                            |> Result.map (Type.field (fieldName |> Name.fromString))
                    )
                |> ResultList.toResult
                |> Result.map
                    (\fields ->
                        Type.record fields sourceLocation
                    )
                |> Result.mapError List.concat

        GenericRecord (Node _ argName) (Node _ fieldNodes) ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldTypeNode ) ->
                        mapTypeAnnotation moduleResolver sourceFile fieldTypeNode
                            |> Result.map (Type.field (fieldName |> Name.fromString))
                    )
                |> ResultList.toResult
                |> Result.map
                    (\fields ->
                        Type.extensibleRecord (argName |> Name.fromString) fields sourceLocation
                    )
                |> Result.mapError List.concat

        FunctionTypeAnnotation argTypeNode returnTypeNode ->
            Result.map2
                (\argType returnType ->
                    Type.function argType returnType sourceLocation
                )
                (mapTypeAnnotation moduleResolver sourceFile argTypeNode)
                (mapTypeAnnotation moduleResolver sourceFile returnTypeNode)


withAccessControl : Bool -> a -> AccessControlled a
withAccessControl isExposed a =
    if isExposed then
        public a

    else
        private a
