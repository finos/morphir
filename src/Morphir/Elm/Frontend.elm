{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.Elm.Frontend exposing
    ( packageDefinitionFromSource, mapDeclarationsToType
    , defaultDependencies
    , Options, ContentLocation, ContentRange, Error(..), Errors, PackageInfo, SourceFile, SourceLocation, mapSource
    , mapValueToFile
    , parseRawValue
    )

{-| The Elm frontend turns Elm source code into Morphir IR.


# Entry points

@docs packageDefinitionFromSource, mapDeclarationsToType


# Utilities

@docs defaultDependencies

@docs Options, ContentLocation, ContentRange, Error, Errors, PackageInfo, SourceFile, SourceLocation, mapSource
@docs mapValueToFile
@docs parseRawValue

-}

import Dict exposing (Dict)
import Elm.Parser
import Elm.Processing as Processing exposing (ProcessContext)
import Elm.RawFile as RawFile exposing (RawFile)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression exposing (Expression, Function)
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Module as ElmModule
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern(..))
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.TypeAnnotation exposing (TypeAnnotation(..))
import Graph exposing (Graph)
import Json.Encode as Encode
import Morphir.Compiler as Compiler
import Morphir.Elm.Frontend.Resolve as Resolve exposing (ModuleResolver)
import Morphir.Elm.IncrementalFrontend as IncrementalFrontend
import Morphir.Elm.WellKnownOperators as WellKnownOperators
import Morphir.Graph
import Morphir.IR.AccessControlled exposing (AccessControlled, private, public)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (fQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Basics as SDKBasics
import Morphir.IR.SDK.List as List
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Type.Rewrite exposing (rewriteType)
import Morphir.IR.Value as Value exposing (RawValue, Value)
import Morphir.Rewrite as Rewrite
import Morphir.SDK.ResultList as ListOfResults
import Morphir.Type.Infer as Infer
import Morphir.Type.Infer.Codec exposing (encodeTypeError)
import Parser exposing (DeadEnd)
import Set exposing (Set)


{-| Options that modify the behavior of the frontend:

    - `typesOnly` - only include type information in the IR, no values

-}
type alias Options =
    { typesOnly : Bool
    }


{-| -}
type alias PackageInfo =
    { name : Path
    , exposedModules : Maybe (Set Path)
    }


{-| -}
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


{-| -}
type alias SourceLocation =
    { source : SourceFile
    , range : ContentRange
    }


{-| -}
type alias ContentRange =
    { start : ContentLocation
    , end : ContentLocation
    }


{-| -}
type alias ContentLocation =
    { row : Int
    , column : Int
    }


{-| -}
type alias Errors =
    List Error


{-| -}
type Error
    = ParseError String (List Parser.DeadEnd)
    | CyclicModules (Morphir.Graph.Graph () (List String))
    | ResolveError SourceLocation Resolve.Error
    | EmptyApply SourceLocation
    | NotSupported SourceLocation String
    | DuplicateNameInPattern Name SourceLocation SourceLocation
    | VariableShadowing Name SourceLocation SourceLocation
    | MissingTypeSignature SourceLocation
    | RecordPatternNotSupported SourceLocation
    | TypeInferenceError SourceLocation Infer.TypeError


type alias Imports =
    { lookupByExposedCtor : String -> Maybe Import
    , byModuleName : Dict ModuleName Import
    }


type alias Import =
    { packagePath : Path
    , modulePath : Path
    , exposesCtor : String -> Bool
    }


{-| Dependencies that are added by default without explicit reference.
-}
defaultDependencies : Dict Path (Package.Specification ())
defaultDependencies =
    Dict.fromList
        [ ( SDK.packageName, SDK.packageSpec )
        ]


{-| Parses an expression written in the Elm syntax into a RawValue.
-}
parseRawValue : Distribution -> String -> Result String RawValue
parseRawValue ir valueSourceCode =
    let
        dummyPackageName : Path
        dummyPackageName =
            Path.fromString "Morphir.Elm.Frontend"

        dummyModuleName : Path
        dummyModuleName =
            Path.fromString "ParseValue"

        dummyValueName : Name
        dummyValueName =
            Name.fromString "morphirElmFrontendParseValue"

        dummyModuleSource : String
        dummyModuleSource =
            String.join "\n"
                [ "module " ++ Path.toString Name.toTitleCase "." (dummyPackageName ++ dummyModuleName) ++ " exposing (..)"
                , ""
                , Name.toCamelCase dummyValueName ++ " = " ++ valueSourceCode
                ]

        dummyModule =
            { path = Path.toString Name.toTitleCase "/" dummyModuleName ++ ".elm"
            , content = dummyModuleSource
            }

        packageInfo =
            { name =
                dummyPackageName
            , exposedModules =
                Just
                    (Set.fromList
                        [ dummyModuleName
                        ]
                    )
            }
    in
    mapSource (Options False) packageInfo defaultDependencies [ dummyModule ]
        |> Result.mapError (always "Unknown error")
        |> Result.andThen
            (\packageDef ->
                packageDef
                    |> Package.mapDefinitionAttributes (always ()) (always ())
                    |> .modules
                    |> Dict.get dummyModuleName
                    |> Maybe.andThen
                        (\moduleDef ->
                            moduleDef.value.values
                                |> Dict.get dummyValueName
                                |> Maybe.map (.value >> .value >> .body)
                        )
                    |> Result.fromMaybe "Cannot find parsed value"
            )


{-| -}
mapValueToFile : Distribution -> Type () -> String -> Result String Distribution
mapValueToFile ir outputType content =
    let
        sourceA =
            { path = "My/Package/A.elm"
            , content =
                String.join "\n"
                    [ "module My.Package.A exposing (..)"
                    , ""
                    , "fooFunction : " ++ (outputType |> Type.toString |> String.replace "Morphir.SDK." "")
                    , ""
                    , "fooFunction = " ++ content
                    ]
            }

        packageName =
            Path.fromString "My.Package"

        moduleA =
            Path.fromString "A"

        packageInfo =
            { name =
                packageName
            , exposedModules =
                Just
                    (Set.fromList
                        [ moduleA
                        ]
                    )
            }
    in
    mapSource (Options False) packageInfo defaultDependencies [ sourceA ]
        |> Result.map
            (\packageDef ->
                packageDef
                    |> Package.mapDefinitionAttributes (\_ -> ()) identity
                    |> Package.mapDefinitionAttributes identity (\_ -> outputType)
                    |> Library packageName Dict.empty
            )
        |> Result.mapError (always "Unknown error")



--Encode.list CompilerCodec.encodeError


{-| -}
mapSource : Options -> PackageInfo -> Dict Path (Package.Specification ()) -> List SourceFile -> Result (List Compiler.Error) (Package.Definition SourceLocation SourceLocation)
mapSource opts packageInfo dependencies sourceFiles =
    let
        mapSourceLocations : String -> SourceLocation -> List SourceLocation -> List ( String, Compiler.ErrorInSourceFile )
        mapSourceLocations message sourceLocation moreSourceLocations =
            [ ( sourceLocation.source.path
              , { errorMessage = message
                , sourceLocations =
                    (sourceLocation :: moreSourceLocations)
                        |> List.map (.range >> mapContentRange)
                }
              )
            ]

        mapContentRange : ContentRange -> Compiler.SourceRange
        mapContentRange contentRange =
            contentRange

        mapParserProblem : Parser.Problem -> String
        mapParserProblem problem =
            case problem of
                Parser.Expecting something ->
                    "Expecting " ++ something

                Parser.ExpectingInt ->
                    "Expecting integer"

                Parser.ExpectingHex ->
                    "Expecting hexadecimal"

                Parser.ExpectingOctal ->
                    "Expecting octal"

                Parser.ExpectingBinary ->
                    "Expecting binary"

                Parser.ExpectingFloat ->
                    "Expecting float"

                Parser.ExpectingNumber ->
                    "Expecting number"

                Parser.ExpectingVariable ->
                    "Expecting variable"

                Parser.ExpectingSymbol symbol ->
                    "Expecting symbol: " ++ symbol

                Parser.ExpectingKeyword keyword ->
                    "Expecting keyword: " ++ keyword

                Parser.ExpectingEnd ->
                    "Expecting end"

                Parser.UnexpectedChar ->
                    "Unexpected character"

                Parser.Problem message ->
                    "Problem: " ++ message

                Parser.BadRepeat ->
                    "Bad repeat"

        mapParserDeadEnd : Parser.DeadEnd -> Compiler.ErrorInSourceFile
        mapParserDeadEnd deadEnd =
            let
                location =
                    { row = deadEnd.row
                    , column = deadEnd.col
                    }
            in
            { errorMessage = "Parse error: " ++ mapParserProblem deadEnd.problem
            , sourceLocations =
                [ { start = location
                  , end = location
                  }
                ]
            }
    in
    packageDefinitionFromSource opts packageInfo dependencies sourceFiles
        |> Result.mapError
            (\errors ->
                let
                    fileSpecificErrors : List Compiler.Error
                    fileSpecificErrors =
                        errors
                            |> List.concatMap
                                (\error ->
                                    case error of
                                        ParseError filePath deadEnds ->
                                            deadEnds
                                                |> List.map (mapParserDeadEnd >> Tuple.pair filePath)

                                        CyclicModules _ ->
                                            []

                                        ResolveError sourceLocation message ->
                                            mapSourceLocations
                                                ("Resolve error: " ++ Resolve.errorToMessage message)
                                                sourceLocation
                                                []

                                        EmptyApply sourceLocation ->
                                            mapSourceLocations
                                                "Empty apply"
                                                sourceLocation
                                                []

                                        NotSupported sourceLocation string ->
                                            mapSourceLocations
                                                ("Not supported: " ++ string)
                                                sourceLocation
                                                []

                                        DuplicateNameInPattern name sourceLocation sourceLocation2 ->
                                            mapSourceLocations
                                                ("Duplicate name in pattern: " ++ Name.toCamelCase name)
                                                sourceLocation
                                                [ sourceLocation2 ]

                                        VariableShadowing name sourceLocation sourceLocation2 ->
                                            mapSourceLocations
                                                ("Variable shadowing: " ++ Name.toCamelCase name)
                                                sourceLocation
                                                [ sourceLocation2 ]

                                        MissingTypeSignature sourceLocation ->
                                            mapSourceLocations
                                                "Missing type signature"
                                                sourceLocation
                                                []

                                        RecordPatternNotSupported sourceLocation ->
                                            mapSourceLocations
                                                "Record pattern not supported"
                                                sourceLocation
                                                []

                                        TypeInferenceError sourceLocation typeError ->
                                            mapSourceLocations
                                                ("Type inference error: " ++ Encode.encode 0 (encodeTypeError typeError))
                                                sourceLocation
                                                []
                                )
                            |> List.foldl
                                (\( filePath, fileError ) soFar ->
                                    soFar
                                        |> Dict.update filePath
                                            (\maybeErrorsSoFar ->
                                                case maybeErrorsSoFar of
                                                    Just errorsSoFar ->
                                                        Just (fileError :: errorsSoFar)

                                                    Nothing ->
                                                        Just [ fileError ]
                                            )
                                )
                                Dict.empty
                            |> Dict.toList
                            |> List.map
                                (\( filePath, fileErrors ) ->
                                    Compiler.ErrorsInSourceFile filePath fileErrors
                                )

                    globalErrors : List Compiler.Error
                    globalErrors =
                        errors
                            |> List.filterMap
                                (\error ->
                                    case error of
                                        CyclicModules graph ->
                                            Just
                                                (Compiler.ErrorAcrossSourceFiles
                                                    { errorMessage = "Module imports form a cycle"
                                                    , files =
                                                        graph
                                                            |> Morphir.Graph.nodeLabels
                                                            |> Set.toList
                                                            |> List.map (String.join "/")
                                                    }
                                                )

                                        _ ->
                                            Nothing
                                )
                in
                fileSpecificErrors ++ globalErrors
            )


{-| Function that takes some package info and a list of sources and returns Morphir IR or errors.
-}
packageDefinitionFromSource : Options -> PackageInfo -> Dict Path (Package.Specification ()) -> List SourceFile -> Result Errors (Package.Definition SourceLocation SourceLocation)
packageDefinitionFromSource opts packageInfo dependencies sourceFiles =
    let
        parseSources : List SourceFile -> Result Errors (List ( ModuleName, ParsedFile ))
        parseSources sources =
            sources
                |> List.map
                    (\sourceFile ->
                        --let
                        --    _ =
                        --        Debug.log "Parsing source" sourceFile.path
                        --in
                        Elm.Parser.parse sourceFile.content
                            |> Result.map
                                (\rawFile ->
                                    ( rawFile |> RawFile.moduleName
                                    , ParsedFile sourceFile rawFile
                                    )
                                )
                            |> Result.mapError (ParseError sourceFile.path)
                    )
                |> ListOfResults.keepAllErrors

        treeShakeModules : Set ModuleName -> List ( ModuleName, ParsedFile ) -> List ( ModuleName, ParsedFile )
        treeShakeModules exposedModuleNames allModules =
            let
                allUsedModules : Set ModuleName
                allUsedModules =
                    allModules
                        |> List.map
                            (\( moduleName, parsedFile ) ->
                                ( ()
                                , moduleName
                                , parsedFile.rawFile
                                    |> RawFile.imports
                                    |> List.map (.moduleName >> Node.value)
                                )
                            )
                        |> Morphir.Graph.fromList
                        |> Morphir.Graph.reachableNodes exposedModuleNames
            in
            allModules
                |> List.filter
                    (\( moduleName, _ ) ->
                        allUsedModules |> Set.member moduleName
                    )

        sortModules : List ( ModuleName, ParsedFile ) -> Result Errors (List ModuleName)
        sortModules modules =
            let
                ( sortedModules, cycles ) =
                    modules
                        |> List.map
                            (\( moduleName, parsedFile ) ->
                                ( ()
                                , moduleName
                                , parsedFile.rawFile
                                    |> RawFile.imports
                                    |> List.map (.moduleName >> Node.value)
                                )
                            )
                        |> Morphir.Graph.fromList
                        |> Morphir.Graph.topologicalSort
            in
            if Morphir.Graph.isEmpty cycles then
                Ok (sortedModules |> List.reverse)

            else
                Err [ CyclicModules cycles ]
    in
    case packageInfo.exposedModules of
        Just exposedModules ->
            let
                exposedModuleNames : Set ModuleName
                exposedModuleNames =
                    exposedModules
                        |> Set.map
                            (\modulePath ->
                                (packageInfo.name |> Path.toList)
                                    ++ (modulePath |> Path.toList)
                                    |> List.map Name.toTitleCase
                            )
            in
            parseSources sourceFiles
                |> Result.andThen
                    (\parsedFiles ->
                        let
                            --_ =
                            --    Debug.log "Parsed sources" (parsedFiles |> List.length)
                            --
                            parsedFilesByModuleName =
                                parsedFiles
                                    |> Dict.fromList
                        in
                        parsedFiles
                            |> treeShakeModules exposedModuleNames
                            |> sortModules
                            |> Result.andThen (mapParsedFiles opts dependencies packageInfo.name parsedFilesByModuleName)
                    )
                |> Result.map
                    (\moduleDefs ->
                        let
                            implicitlyExposedModules : Set Path
                            implicitlyExposedModules =
                                IncrementalFrontend.collectImplicitlyExposedModules packageInfo.name moduleDefs exposedModules
                        in
                        { modules =
                            moduleDefs
                                |> Dict.toList
                                |> List.map
                                    (\( modulePath, m ) ->
                                        if Set.member modulePath exposedModules then
                                            ( modulePath, public m )

                                        else if Set.member modulePath implicitlyExposedModules then
                                            -- Module is implicitly exposed. Make it public
                                            ( modulePath, public m )

                                        else
                                            ( modulePath, private m )
                                    )
                                |> Dict.fromList
                        }
                    )

        Nothing ->
            parseSources sourceFiles
                |> Result.andThen
                    (\parsedFiles ->
                        let
                            --_ =
                            --    Debug.log "Parsed sources" (parsedFiles |> List.length)
                            --
                            parsedFilesByModuleName =
                                parsedFiles
                                    |> Dict.fromList
                        in
                        parsedFiles
                            |> sortModules
                            |> Result.andThen (mapParsedFiles opts dependencies packageInfo.name parsedFilesByModuleName)
                    )
                |> Result.map
                    (\moduleDefs ->
                        { modules =
                            moduleDefs
                                |> Dict.toList
                                |> List.map
                                    (\( modulePath, m ) ->
                                        ( modulePath, public m )
                                    )
                                |> Dict.fromList
                        }
                    )


mapParsedFiles : Options -> Dict Path (Package.Specification ()) -> Path -> Dict ModuleName ParsedFile -> List ModuleName -> Result Errors (Dict Path (Module.Definition SourceLocation SourceLocation))
mapParsedFiles opts dependencies currentPackagePath parsedModules sortedModuleNames =
    let
        initialContext : ProcessContext
        initialContext =
            Processing.init
                |> withWellKnownOperators
    in
    sortedModuleNames
        |> List.filterMap
            (\moduleName ->
                parsedModules
                    |> Dict.get moduleName
            )
        |> List.foldl
            (\parsedFile moduleResultsSoFar ->
                moduleResultsSoFar
                    |> Result.andThen
                        (\( processContext, modulesSoFar ) ->
                            let
                                processedFile : File
                                processedFile =
                                    parsedFile.rawFile
                                        |> Processing.process processContext

                                newProcessContext : ProcessContext
                                newProcessContext =
                                    processContext
                                        |> Processing.addFile parsedFile.rawFile
                            in
                            mapProcessedFile opts dependencies currentPackagePath (ProcessedFile parsedFile processedFile) modulesSoFar
                                |> Result.map (Tuple.pair newProcessContext)
                        )
            )
            (Ok ( initialContext, Dict.empty ))
        |> Result.map Tuple.second


mapProcessedFile : Options -> Dict Path (Package.Specification ()) -> Path -> ProcessedFile -> Dict Path (Module.Definition SourceLocation SourceLocation) -> Result Errors (Dict Path (Module.Definition SourceLocation SourceLocation))
mapProcessedFile opts dependencies currentPackagePath processedFile modulesSoFar =
    let
        modulePath =
            processedFile.file.moduleDefinition
                |> Node.value
                |> ElmModule.moduleName
                |> List.map Name.fromString
                |> Path.fromList
                |> List.drop (List.length currentPackagePath)

        moduleExpose =
            processedFile.file.moduleDefinition
                |> Node.value
                |> ElmModule.exposingList

        moduleDeclsSoFar : Dict Path (Module.Specification ())
        moduleDeclsSoFar =
            modulesSoFar
                |> Dict.map
                    (\_ def ->
                        Module.definitionToSpecification def
                            |> Module.eraseSpecificationAttributes
                    )

        typesResult : Result Errors (Dict Name (AccessControlled (Documented (Type.Definition SourceLocation))))
        typesResult =
            mapDeclarationsToType processedFile.parsedFile.sourceFile moduleExpose (processedFile.file.declarations |> List.map Node.value)
                |> Result.map Dict.fromList

        valuesResult : Result Errors (Dict Name (AccessControlled (Documented (Value.Definition SourceLocation SourceLocation))))
        valuesResult =
            if opts.typesOnly then
                Ok Dict.empty

            else
                mapDeclarationsToValue processedFile.parsedFile.sourceFile moduleExpose processedFile.file.declarations
                    |> Result.map Dict.fromList

        documentationResult : Result error (Maybe String)
        documentationResult =
            Ok <|
                if List.isEmpty processedFile.file.comments then
                    Nothing

                else
                    processedFile.file.comments
                        |> List.map Node.value
                        |> List.filter (String.startsWith "{-|")
                        |> List.head
                        |> Maybe.map (String.dropLeft 3 >> String.dropRight 3)

        moduleResult : Result Errors (Module.Definition SourceLocation SourceLocation)
        moduleResult =
            Result.map3 Module.Definition
                typesResult
                valuesResult
                documentationResult
    in
    moduleResult
        |> Result.andThen
            (\moduleDef ->
                let
                    moduleResolver : ModuleResolver
                    moduleResolver =
                        Resolve.createModuleResolver
                            (Resolve.Context
                                (Dict.union defaultDependencies dependencies)
                                currentPackagePath
                                moduleDeclsSoFar
                                (processedFile.file.imports |> List.map Node.value)
                                modulePath
                                moduleDef
                            )
                in
                resolveLocalNames moduleResolver moduleDef
            )
        |> Result.map
            (\m ->
                modulesSoFar
                    |> Dict.insert modulePath m
            )


{-| Function that turns `elm-syntax` declarations to Morphir IR types.
-}
mapDeclarationsToType : SourceFile -> Exposing -> List Declaration -> Result Errors (List ( Name, AccessControlled (Documented (Type.Definition SourceLocation)) ))
mapDeclarationsToType sourceFile expose decls =
    decls
        |> List.filterMap
            (\decl ->
                case decl of
                    AliasDeclaration typeAlias ->
                        mapTypeAnnotation sourceFile typeAlias.typeAnnotation
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

                                        doc =
                                            typeAlias.documentation
                                                |> Maybe.map (Node.value >> String.dropLeft 3 >> String.dropRight 2)
                                                |> Maybe.withDefault ""
                                    in
                                    ( name, withAccessControl isExposed (Documented doc (Type.typeAliasDefinition typeParams typeExp)) )
                                )
                            |> Just

                    CustomTypeDeclaration customType ->
                        let
                            ( isTypeExposed, isCtorExposed ) =
                                case expose of
                                    Exposing.All _ ->
                                        ( True, True )

                                    Exposing.Explicit exposeList ->
                                        exposeList
                                            |> List.map Node.value
                                            |> List.filterMap
                                                (\topLevelExpose ->
                                                    case topLevelExpose of
                                                        Exposing.TypeOrAliasExpose exposedName ->
                                                            if exposedName == Node.value customType.name then
                                                                Just False

                                                            else
                                                                Nothing

                                                        Exposing.TypeExpose exposedType ->
                                                            if exposedType.name == Node.value customType.name then
                                                                case exposedType.open of
                                                                    Just _ ->
                                                                        Just True

                                                                    Nothing ->
                                                                        Just False

                                                            else
                                                                Nothing

                                                        _ ->
                                                            Nothing
                                                )
                                            |> List.head
                                            |> Maybe.map (\isOpen -> ( True, isOpen ))
                                            |> Maybe.withDefault ( False, False )

                            name =
                                customType.name
                                    |> Node.value
                                    |> Name.fromString

                            typeParams =
                                customType.generics
                                    |> List.map (Node.value >> Name.fromString)

                            ctorsResult : Result Errors (Type.Constructors SourceLocation)
                            ctorsResult =
                                customType.constructors
                                    |> List.map
                                        (\ctorNode ->
                                            let
                                                ctor =
                                                    ctorNode
                                                        |> Node.value

                                                ctorName =
                                                    ctor.name
                                                        |> Node.value
                                                        |> Name.fromString

                                                ctorArgsResult : Result Errors (List ( Name, Type SourceLocation ))
                                                ctorArgsResult =
                                                    ctor.arguments
                                                        |> List.indexedMap
                                                            (\index arg ->
                                                                mapTypeAnnotation sourceFile arg
                                                                    |> Result.map
                                                                        (\argType ->
                                                                            ( [ "arg", String.fromInt (index + 1) ]
                                                                            , argType
                                                                            )
                                                                        )
                                                            )
                                                        |> ListOfResults.keepAllErrors
                                                        |> Result.mapError List.concat
                                            in
                                            ctorArgsResult
                                                |> Result.map
                                                    (\ctorArgs ->
                                                        ( ctorName, ctorArgs )
                                                    )
                                        )
                                    |> ListOfResults.keepAllErrors
                                    |> Result.map Dict.fromList
                                    |> Result.mapError List.concat

                            doc : String
                            doc =
                                customType.documentation
                                    |> Maybe.map (Node.value >> String.dropLeft 3 >> String.dropRight 2)
                                    |> Maybe.withDefault ""
                        in
                        ctorsResult
                            |> Result.map
                                (\constructors ->
                                    ( name, withAccessControl isTypeExposed (Documented doc (Type.customTypeDefinition typeParams (withAccessControl isCtorExposed constructors))) )
                                )
                            |> Just

                    _ ->
                        Nothing
            )
        |> ListOfResults.keepAllErrors
        |> Result.mapError List.concat


mapDeclarationsToValue : SourceFile -> Exposing -> List (Node Declaration) -> Result Errors (List ( Name, AccessControlled (Documented (Value.Definition SourceLocation SourceLocation)) ))
mapDeclarationsToValue sourceFile expose decls =
    decls
        |> List.filterMap
            (\(Node range decl) ->
                case decl of
                    FunctionDeclaration function ->
                        let
                            valueName : Name
                            valueName =
                                function.declaration
                                    |> Node.value
                                    |> .name
                                    |> Node.value
                                    |> Name.fromString

                            doc : String
                            doc =
                                function.documentation
                                    |> Maybe.map (Node.value >> String.dropLeft 3 >> String.dropRight 2)
                                    |> Maybe.withDefault ""

                            valueDef : Result Errors (AccessControlled (Documented (Value.Definition SourceLocation SourceLocation)))
                            valueDef =
                                Node range function
                                    |> mapFunction sourceFile
                                    |> Result.map (Documented doc)
                                    |> Result.map public
                        in
                        valueDef
                            |> Result.map (Tuple.pair valueName)
                            |> Just

                    _ ->
                        Nothing
            )
        |> ListOfResults.keepAllErrors
        |> Result.mapError List.concat


mapTypeAnnotation : SourceFile -> Node TypeAnnotation -> Result Errors (Type SourceLocation)
mapTypeAnnotation sourceFile (Node range typeAnnotation) =
    let
        sourceLocation =
            range |> SourceLocation sourceFile
    in
    case typeAnnotation of
        GenericType varName ->
            Ok (Type.Variable sourceLocation (varName |> Name.fromString))

        Typed (Node _ ( moduleName, localName )) argNodes ->
            Result.map
                (Type.Reference sourceLocation (fQName [] (moduleName |> List.map Name.fromString) (Name.fromString localName)))
                (argNodes
                    |> List.map (mapTypeAnnotation sourceFile)
                    |> ListOfResults.keepAllErrors
                    |> Result.mapError List.concat
                )

        Unit ->
            Ok (Type.Unit sourceLocation)

        Tupled elemNodes ->
            elemNodes
                |> List.map (mapTypeAnnotation sourceFile)
                |> ListOfResults.keepAllErrors
                |> Result.map (Type.Tuple sourceLocation)
                |> Result.mapError List.concat

        Record fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldTypeNode ) ->
                        mapTypeAnnotation sourceFile fieldTypeNode
                            |> Result.map (Type.Field (fieldName |> Name.fromString))
                    )
                |> ListOfResults.keepAllErrors
                |> Result.map (Type.Record sourceLocation)
                |> Result.mapError List.concat

        GenericRecord (Node _ argName) (Node _ fieldNodes) ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldTypeNode ) ->
                        mapTypeAnnotation sourceFile fieldTypeNode
                            |> Result.map (Type.Field (fieldName |> Name.fromString))
                    )
                |> ListOfResults.keepAllErrors
                |> Result.map (Type.ExtensibleRecord sourceLocation (argName |> Name.fromString))
                |> Result.mapError List.concat

        FunctionTypeAnnotation argTypeNode returnTypeNode ->
            Result.map2 (Type.Function sourceLocation)
                (mapTypeAnnotation sourceFile argTypeNode)
                (mapTypeAnnotation sourceFile returnTypeNode)


mapFunction : SourceFile -> Node Function -> Result Errors (Value.Definition SourceLocation SourceLocation)
mapFunction sourceFile (Node functionRange function) =
    let
        sourceLocation : Range -> SourceLocation
        sourceLocation range =
            range |> SourceLocation sourceFile

        expression : Node Expression
        expression =
            Node
                functionRange
                (Expression.LambdaExpression
                    { args =
                        function.declaration
                            |> Node.value
                            |> .arguments
                    , expression =
                        function.declaration
                            |> Node.value
                            |> .expression
                    }
                )
    in
    case function.signature of
        Just (Node _ signature) ->
            mapTypeAnnotation sourceFile signature.typeAnnotation
                |> Result.andThen
                    (\declaredType ->
                        mapExpression sourceFile expression
                            |> Result.map (Value.Definition [] declaredType)
                    )
                |> Result.map liftLambdaArguments

        Nothing ->
            let
                exp =
                    mapExpression sourceFile expression

                emptyDistribution : Distribution
                emptyDistribution =
                    Library [ [ "empty" ] ] Dict.empty Package.emptyDefinition
            in
            exp
                |> Result.andThen
                    (\body ->
                        Infer.inferValue emptyDistribution (body |> Value.mapValueAttributes (always ()) identity)
                            |> Result.mapError (\err -> [ TypeInferenceError (sourceLocation functionRange) err ])
                            |> Result.map (Value.valueAttribute >> Tuple.second >> Type.mapTypeAttributes (always (sourceLocation functionRange)))
                    )
                |> Result.andThen
                    (\inferredType ->
                        exp
                            |> Result.map (Value.Definition [] inferredType)
                    )
                |> Result.map liftLambdaArguments


{-| Moves lambda arguments into function arguments as much as possible. For example given this function definition:

    foo : Int -> Bool -> ( Int, Int ) -> String
    foo =
        \a ->
            \b ->
                ( c, d ) ->
                    doSomething a b c d

It turns it into the following:

    foo : Int -> Bool -> ( Int, Int ) -> String
    foo a b =
        ( c, d ) ->
            doSomething a b c d

-}
liftLambdaArguments : Value.Definition ta va -> Value.Definition ta va
liftLambdaArguments valueDef =
    case ( valueDef.body, valueDef.outputType ) of
        ( Value.Lambda va (Value.AsPattern _ (Value.WildcardPattern _) argName) lambdaBody, Type.Function _ argType returnType ) ->
            liftLambdaArguments
                { inputTypes = valueDef.inputTypes ++ [ ( argName, va, argType ) ]
                , outputType = returnType
                , body = lambdaBody
                }

        _ ->
            valueDef


mapExpression : SourceFile -> Node Expression -> Result Errors (Value.Value SourceLocation SourceLocation)
mapExpression sourceFile (Node range exp) =
    let
        sourceLocation =
            range |> SourceLocation sourceFile
    in
    case exp of
        Expression.UnitExpr ->
            Ok (Value.Unit sourceLocation)

        Expression.Application expNodes ->
            let
                toApply : List (Value.Value SourceLocation SourceLocation) -> Result Errors (Value.Value SourceLocation SourceLocation)
                toApply valuesReversed =
                    case valuesReversed of
                        [] ->
                            Err [ EmptyApply sourceLocation ]

                        [ singleValue ] ->
                            Ok singleValue

                        lastValue :: restOfValuesReversed ->
                            toApply restOfValuesReversed
                                |> Result.map
                                    (\funValue ->
                                        Value.Apply sourceLocation funValue lastValue
                                    )
            in
            expNodes
                |> List.map (mapExpression sourceFile)
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.andThen (List.reverse >> toApply)

        Expression.OperatorApplication op _ leftNode rightNode ->
            case op of
                "<|" ->
                    -- the purpose of this operator is cleaner syntax so it's not mapped to the IR
                    Result.map2 (Value.Apply sourceLocation)
                        (mapExpression sourceFile leftNode)
                        (mapExpression sourceFile rightNode)

                "|>" ->
                    -- the purpose of this operator is cleaner syntax so it's not mapped to the IR
                    Result.map2 (Value.Apply sourceLocation)
                        (mapExpression sourceFile rightNode)
                        (mapExpression sourceFile leftNode)

                _ ->
                    Result.map3 (\fun arg1 arg2 -> Value.Apply sourceLocation (Value.Apply sourceLocation fun arg1) arg2)
                        (mapOperator sourceLocation op)
                        (mapExpression sourceFile leftNode)
                        (mapExpression sourceFile rightNode)

        Expression.FunctionOrValue moduleName localName ->
            localName
                |> String.uncons
                |> Result.fromMaybe [ NotSupported sourceLocation "Empty value name" ]
                |> Result.andThen
                    (\( firstChar, _ ) ->
                        if Char.isUpper firstChar then
                            case ( moduleName, localName ) of
                                ( [], "True" ) ->
                                    Ok (Value.Literal sourceLocation (BoolLiteral True))

                                ( [], "False" ) ->
                                    Ok (Value.Literal sourceLocation (BoolLiteral False))

                                _ ->
                                    Ok (Value.Constructor sourceLocation (fQName [] (moduleName |> List.map Name.fromString) (localName |> Name.fromString)))

                        else
                            Ok (Value.Reference sourceLocation (fQName [] (moduleName |> List.map Name.fromString) (localName |> Name.fromString)))
                    )

        Expression.IfBlock condNode thenNode elseNode ->
            Result.map3 (Value.IfThenElse sourceLocation)
                (mapExpression sourceFile condNode)
                (mapExpression sourceFile thenNode)
                (mapExpression sourceFile elseNode)

        Expression.PrefixOperator op ->
            mapOperator sourceLocation op

        Expression.Operator op ->
            mapOperator sourceLocation op

        Expression.Integer value ->
            Ok (Value.Literal sourceLocation (WholeNumberLiteral value))

        Expression.Hex value ->
            Ok (Value.Literal sourceLocation (WholeNumberLiteral value))

        Expression.Floatable value ->
            Ok (Value.Literal sourceLocation (FloatLiteral value))

        Expression.Negation arg ->
            mapExpression sourceFile arg
                |> Result.map (SDKBasics.negate sourceLocation sourceLocation)

        Expression.Literal value ->
            Ok (Value.Literal sourceLocation (StringLiteral value))

        Expression.CharLiteral value ->
            Ok (Value.Literal sourceLocation (CharLiteral value))

        Expression.TupledExpression expNodes ->
            expNodes
                |> List.map (mapExpression sourceFile)
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.Tuple sourceLocation)

        Expression.ParenthesizedExpression expNode ->
            mapExpression sourceFile expNode

        Expression.LetExpression letBlock ->
            mapLetExpression sourceFile sourceLocation letBlock

        Expression.CaseExpression caseBlock ->
            Result.map2 (Value.PatternMatch sourceLocation)
                (mapExpression sourceFile caseBlock.expression)
                (caseBlock.cases
                    |> List.map
                        (\( patternNode, bodyNode ) ->
                            Result.map2 Tuple.pair
                                (mapPattern sourceFile patternNode)
                                (mapExpression sourceFile bodyNode)
                        )
                    |> ListOfResults.keepAllErrors
                    |> Result.mapError List.concat
                )

        Expression.LambdaExpression lambda ->
            let
                curriedLambda : List (Node Pattern) -> Node Expression -> Result Errors (Value.Value SourceLocation SourceLocation)
                curriedLambda argNodes bodyNode =
                    case argNodes of
                        [] ->
                            mapExpression sourceFile bodyNode

                        firstArgNode :: restOfArgNodes ->
                            Result.map2 (Value.Lambda sourceLocation)
                                (mapPattern sourceFile firstArgNode)
                                (curriedLambda restOfArgNodes bodyNode)
            in
            curriedLambda lambda.args lambda.expression

        Expression.RecordExpr fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldValue ) ->
                        mapExpression sourceFile fieldValue
                            |> Result.map (Tuple.pair (fieldName |> Name.fromString))
                    )
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map Dict.fromList
                |> Result.map (Value.Record sourceLocation)

        Expression.ListExpr itemNodes ->
            itemNodes
                |> List.map (mapExpression sourceFile)
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.List sourceLocation)

        Expression.RecordAccess targetNode fieldNameNode ->
            mapExpression sourceFile targetNode
                |> Result.map
                    (\subjectValue ->
                        Value.Field sourceLocation subjectValue (fieldNameNode |> Node.value |> Name.fromString)
                    )

        Expression.RecordAccessFunction fieldName ->
            Ok (Value.FieldFunction sourceLocation (fieldName |> Name.fromString))

        Expression.RecordUpdateExpression targetVarNameNode fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldValue ) ->
                        mapExpression sourceFile fieldValue
                            |> Result.map (Tuple.pair (fieldName |> Name.fromString))
                    )
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map Dict.fromList
                |> Result.map
                    (Value.UpdateRecord sourceLocation (targetVarNameNode |> Node.value |> Name.fromString |> Value.Variable sourceLocation))

        Expression.GLSLExpression _ ->
            Err [ NotSupported sourceLocation "GLSLExpression" ]


mapPattern : SourceFile -> Node Pattern -> Result Errors (Value.Pattern SourceLocation)
mapPattern sourceFile (Node range pattern) =
    let
        sourceLocation =
            range |> SourceLocation sourceFile
    in
    case pattern of
        Pattern.AllPattern ->
            Ok (Value.WildcardPattern sourceLocation)

        Pattern.UnitPattern ->
            Ok (Value.UnitPattern sourceLocation)

        Pattern.CharPattern char ->
            Ok (Value.LiteralPattern sourceLocation (CharLiteral char))

        Pattern.StringPattern string ->
            Ok (Value.LiteralPattern sourceLocation (StringLiteral string))

        Pattern.IntPattern int ->
            Ok (Value.LiteralPattern sourceLocation (WholeNumberLiteral int))

        Pattern.HexPattern int ->
            Ok (Value.LiteralPattern sourceLocation (WholeNumberLiteral int))

        Pattern.FloatPattern float ->
            Ok (Value.LiteralPattern sourceLocation (FloatLiteral float))

        Pattern.TuplePattern elemNodes ->
            elemNodes
                |> List.map (mapPattern sourceFile)
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.TuplePattern sourceLocation)

        Pattern.RecordPattern fieldNameNodes ->
            Err [ RecordPatternNotSupported sourceLocation ]

        Pattern.UnConsPattern headNode tailNode ->
            Result.map2 (Value.HeadTailPattern sourceLocation)
                (mapPattern sourceFile headNode)
                (mapPattern sourceFile tailNode)

        Pattern.ListPattern itemNodes ->
            let
                toPattern : List (Node Pattern) -> Result Errors (Value.Pattern SourceLocation)
                toPattern patternNodes =
                    case patternNodes of
                        [] ->
                            Ok (Value.EmptyListPattern sourceLocation)

                        headNode :: tailNodes ->
                            Result.map2 (Value.HeadTailPattern sourceLocation)
                                (mapPattern sourceFile headNode)
                                (toPattern tailNodes)
            in
            toPattern itemNodes

        Pattern.VarPattern name ->
            Ok (Value.AsPattern sourceLocation (Value.WildcardPattern sourceLocation) (Name.fromString name))

        Pattern.NamedPattern qualifiedNameRef argNodes ->
            let
                qualifiedName =
                    qualifiedNameRef.name
                        |> Name.fromString
                        |> QName.fromName (qualifiedNameRef.moduleName |> List.map Name.fromString)
                        |> FQName.fromQName []
            in
            case ( qualifiedNameRef.moduleName, qualifiedNameRef.name ) of
                ( [], "True" ) ->
                    Ok (Value.LiteralPattern sourceLocation (BoolLiteral True))

                ( [], "False" ) ->
                    Ok (Value.LiteralPattern sourceLocation (BoolLiteral False))

                _ ->
                    argNodes
                        |> List.map (mapPattern sourceFile)
                        |> ListOfResults.keepAllErrors
                        |> Result.mapError List.concat
                        |> Result.map (Value.ConstructorPattern sourceLocation qualifiedName)

        Pattern.AsPattern subjectNode aliasNode ->
            mapPattern sourceFile subjectNode
                |> Result.map (\subject -> Value.AsPattern sourceLocation subject (aliasNode |> Node.value |> Name.fromString))

        Pattern.ParenthesizedPattern childNode ->
            mapPattern sourceFile childNode


mapOperator : SourceLocation -> String -> Result Errors (Value.Value SourceLocation SourceLocation)
mapOperator sourceLocation op =
    case op of
        "||" ->
            Ok <| SDKBasics.or sourceLocation

        "&&" ->
            Ok <| SDKBasics.and sourceLocation

        "==" ->
            Ok <| SDKBasics.equal sourceLocation

        "/=" ->
            Ok <| SDKBasics.notEqual sourceLocation

        "<" ->
            Ok <| SDKBasics.lessThan sourceLocation

        ">" ->
            Ok <| SDKBasics.greaterThan sourceLocation

        "<=" ->
            Ok <| SDKBasics.lessThanOrEqual sourceLocation

        ">=" ->
            Ok <| SDKBasics.greaterThanOrEqual sourceLocation

        "++" ->
            Ok <| SDKBasics.append sourceLocation

        "+" ->
            Ok <| SDKBasics.add sourceLocation

        "-" ->
            Ok <| SDKBasics.subtract sourceLocation

        "*" ->
            Ok <| SDKBasics.multiply sourceLocation

        "/" ->
            Ok <| SDKBasics.divide sourceLocation

        "//" ->
            Ok <| SDKBasics.integerDivide sourceLocation

        "^" ->
            Ok <| SDKBasics.power sourceLocation

        "<<" ->
            Ok <| SDKBasics.composeLeft sourceLocation

        ">>" ->
            Ok <| SDKBasics.composeRight sourceLocation

        "::" ->
            Ok <| List.construct sourceLocation

        _ ->
            Err [ NotSupported sourceLocation <| "OperatorApplication: " ++ op ]


mapLetExpression : SourceFile -> SourceLocation -> Expression.LetBlock -> Result Errors (Value SourceLocation SourceLocation)
mapLetExpression sourceFile sourceLocation letBlock =
    let
        namesReferredByExpression : Expression -> List String
        namesReferredByExpression expression =
            case expression of
                Expression.Application argNodes ->
                    argNodes |> List.concatMap (Node.value >> namesReferredByExpression)

                Expression.OperatorApplication _ _ (Node _ leftExp) (Node _ rightExp) ->
                    namesReferredByExpression leftExp ++ namesReferredByExpression rightExp

                Expression.FunctionOrValue [] name ->
                    [ name ]

                Expression.IfBlock (Node _ condExp) (Node _ thenExp) (Node _ elseExp) ->
                    namesReferredByExpression condExp ++ namesReferredByExpression thenExp ++ namesReferredByExpression elseExp

                Expression.Negation (Node _ childExp) ->
                    namesReferredByExpression childExp

                Expression.TupledExpression argNodes ->
                    argNodes |> List.concatMap (Node.value >> namesReferredByExpression)

                Expression.ParenthesizedExpression (Node _ childExp) ->
                    namesReferredByExpression childExp

                Expression.LetExpression innerLetBlock ->
                    innerLetBlock.declarations
                        |> List.concatMap
                            (\(Node _ decl) ->
                                case decl of
                                    Expression.LetFunction function ->
                                        function.declaration |> Node.value |> .expression |> Node.value |> namesReferredByExpression

                                    Expression.LetDestructuring _ (Node _ childExp) ->
                                        namesReferredByExpression childExp
                            )
                        |> (++) (innerLetBlock.expression |> Node.value |> namesReferredByExpression)

                Expression.CaseExpression caseBlock ->
                    caseBlock.cases
                        |> List.concatMap
                            (\( _, Node _ childExp ) ->
                                namesReferredByExpression childExp
                            )
                        |> (++) (caseBlock.expression |> Node.value |> namesReferredByExpression)

                Expression.LambdaExpression lambda ->
                    lambda.expression |> Node.value |> namesReferredByExpression

                Expression.RecordExpr setterNodes ->
                    setterNodes |> List.concatMap (\(Node _ ( _, Node _ childExp )) -> namesReferredByExpression childExp)

                Expression.ListExpr argNodes ->
                    argNodes |> List.concatMap (Node.value >> namesReferredByExpression)

                Expression.RecordAccess (Node _ childExp) _ ->
                    namesReferredByExpression childExp

                Expression.RecordUpdateExpression (Node _ recordRef) setterNodes ->
                    recordRef :: (setterNodes |> List.concatMap (\(Node _ ( _, Node _ childExp )) -> namesReferredByExpression childExp))

                _ ->
                    []

        letBlockToValue : List (Node Expression.LetDeclaration) -> Node Expression -> Result Errors (Value.Value SourceLocation SourceLocation)
        letBlockToValue declarationNodes inNode =
            let
                -- build a dictionary from variable name to declaration index
                declarationIndexForName : Dict String Int
                declarationIndexForName =
                    declarationNodes
                        |> List.indexedMap
                            (\index (Node _ decl) ->
                                case decl of
                                    Expression.LetFunction function ->
                                        [ ( function.declaration |> Node.value |> .name |> Node.value, index ) ]

                                    Expression.LetDestructuring (Node _ pattern) _ ->
                                        namesBoundByPattern pattern
                                            |> Set.map (\name -> ( name, index ))
                                            |> Set.toList
                            )
                        |> List.concat
                        |> Dict.fromList

                -- build a dependency graph between declarations
                declarationDependencyGraph : Graph (Node Expression.LetDeclaration) String
                declarationDependencyGraph =
                    let
                        nodes : List (Graph.Node (Node Expression.LetDeclaration))
                        nodes =
                            declarationNodes
                                |> List.indexedMap
                                    (\index declNode ->
                                        Graph.Node index declNode
                                    )

                        edges : List (Graph.Edge String)
                        edges =
                            declarationNodes
                                |> List.indexedMap
                                    (\fromIndex (Node _ decl) ->
                                        case decl of
                                            Expression.LetFunction function ->
                                                function.declaration
                                                    |> Node.value
                                                    |> .expression
                                                    |> Node.value
                                                    |> namesReferredByExpression
                                                    |> List.filterMap
                                                        (\name ->
                                                            declarationIndexForName
                                                                |> Dict.get name
                                                                |> Maybe.map (\toIndex -> Graph.Edge fromIndex toIndex name)
                                                        )

                                            Expression.LetDestructuring _ expression ->
                                                expression
                                                    |> Node.value
                                                    |> namesReferredByExpression
                                                    |> List.filterMap
                                                        (\name ->
                                                            declarationIndexForName
                                                                |> Dict.get name
                                                                |> Maybe.map (\toIndex -> Graph.Edge fromIndex toIndex name)
                                                        )
                                    )
                                |> List.concat
                    in
                    Graph.fromNodesAndEdges nodes edges

                letDeclarationToValue : Node Expression.LetDeclaration -> Result Errors (Value.Value SourceLocation SourceLocation) -> Result Errors (Value.Value SourceLocation SourceLocation)
                letDeclarationToValue letDeclarationNode valueResult =
                    case letDeclarationNode of
                        Node range (Expression.LetFunction function) ->
                            Result.map2 (Value.LetDefinition sourceLocation (function.declaration |> Node.value |> .name |> Node.value |> Name.fromString))
                                (mapFunction sourceFile (Node range function))
                                valueResult

                        Node range (Expression.LetDestructuring patternNode letExpressionNode) ->
                            Result.map3 (Value.Destructure sourceLocation)
                                (mapPattern sourceFile patternNode)
                                (mapExpression sourceFile letExpressionNode)
                                valueResult

                componentGraphToValue : Graph (Node Expression.LetDeclaration) String -> Result Errors (Value.Value SourceLocation SourceLocation) -> Result Errors (Value.Value SourceLocation SourceLocation)
                componentGraphToValue componentGraph valueResult =
                    case componentGraph |> Graph.checkAcyclic of
                        Ok acyclic ->
                            acyclic
                                |> Graph.topologicalSort
                                |> List.foldl
                                    (\nodeContext innerSoFar ->
                                        letDeclarationToValue nodeContext.node.label innerSoFar
                                    )
                                    valueResult

                        Err _ ->
                            Result.map2 (Value.LetRecursion sourceLocation)
                                (componentGraph
                                    |> Graph.nodes
                                    |> List.map
                                        (\graphNode ->
                                            case graphNode.label of
                                                Node range (Expression.LetFunction function) ->
                                                    mapFunction sourceFile (Node range function)
                                                        |> Result.map (Tuple.pair (function.declaration |> Node.value |> .name |> Node.value |> Name.fromString))

                                                Node range (Expression.LetDestructuring _ _) ->
                                                    Err [ NotSupported sourceLocation "Recursive destructuring" ]
                                        )
                                    |> ListOfResults.keepAllErrors
                                    |> Result.mapError List.concat
                                    |> Result.map Dict.fromList
                                )
                                valueResult
            in
            case declarationDependencyGraph |> Graph.stronglyConnectedComponents of
                Ok acyclic ->
                    acyclic
                        |> Graph.topologicalSort
                        |> List.foldl
                            (\nodeContext soFar ->
                                letDeclarationToValue nodeContext.node.label soFar
                            )
                            (mapExpression sourceFile inNode)

                Err components ->
                    components
                        |> List.foldl
                            componentGraphToValue
                            (mapExpression sourceFile inNode)
    in
    letBlockToValue letBlock.declarations letBlock.expression


namesBoundByPattern : Pattern -> Set String
namesBoundByPattern p =
    let
        namesBound : Pattern -> List String
        namesBound pattern =
            case pattern of
                TuplePattern elemPatternNodes ->
                    elemPatternNodes |> List.concatMap (Node.value >> namesBound)

                RecordPattern fieldNameNodes ->
                    fieldNameNodes |> List.map Node.value

                UnConsPattern (Node _ headPattern) (Node _ tailPattern) ->
                    namesBound headPattern ++ namesBound tailPattern

                ListPattern itemPatternNodes ->
                    itemPatternNodes |> List.concatMap (Node.value >> namesBound)

                VarPattern name ->
                    [ name ]

                NamedPattern _ argPatternNodes ->
                    argPatternNodes |> List.concatMap (Node.value >> namesBound)

                AsPattern (Node _ childPattern) (Node _ alias) ->
                    alias :: namesBound childPattern

                ParenthesizedPattern (Node _ childPattern) ->
                    namesBound childPattern

                _ ->
                    []
    in
    namesBound p
        |> Set.fromList


rewriteTypes : ModuleResolver -> Type SourceLocation -> Result Errors (Type SourceLocation)
rewriteTypes moduleResolver =
    Rewrite.bottomUp rewriteType
        (\tpe ->
            case tpe of
                Type.Reference sourceLocation refFullName args ->
                    moduleResolver.resolveType
                        (refFullName |> FQName.getModulePath |> List.map Name.toTitleCase)
                        (refFullName |> FQName.getLocalName |> Name.toTitleCase)
                        |> Result.map
                            (\resolvedFullName ->
                                Type.Reference sourceLocation resolvedFullName args
                            )
                        |> Result.mapError (ResolveError sourceLocation >> List.singleton)
                        |> Just

                _ ->
                    Nothing
        )


resolveLocalNames : ModuleResolver -> Module.Definition SourceLocation SourceLocation -> Result Errors (Module.Definition SourceLocation SourceLocation)
resolveLocalNames moduleResolver moduleDef =
    let
        rewriteValues : Dict Name SourceLocation -> Value SourceLocation SourceLocation -> Result Errors (Value SourceLocation SourceLocation)
        rewriteValues variables value =
            resolveVariablesAndReferences variables moduleResolver value

        typesResult : Result Errors (Dict Name (AccessControlled (Documented (Type.Definition SourceLocation))))
        typesResult =
            moduleDef.types
                |> Dict.toList
                |> List.map
                    (\( typeName, typeDef ) ->
                        typeDef.value.value
                            |> Type.mapDefinition (rewriteTypes moduleResolver)
                            |> Result.map (Documented typeDef.value.doc)
                            |> Result.map (AccessControlled typeDef.access)
                            |> Result.map (Tuple.pair typeName)
                            |> Result.mapError List.concat
                    )
                |> ListOfResults.keepAllErrors
                |> Result.map Dict.fromList
                |> Result.mapError List.concat

        valuesResult : Result Errors (Dict Name (AccessControlled (Documented (Value.Definition SourceLocation SourceLocation))))
        valuesResult =
            moduleDef.values
                |> Dict.toList
                |> List.map
                    (\( valueName, valueDef ) ->
                        let
                            variables : Dict Name SourceLocation
                            variables =
                                valueDef.value.value.inputTypes
                                    |> List.map (\( name, loc, _ ) -> ( name, loc ))
                                    |> Dict.fromList
                        in
                        valueDef.value.value
                            |> Value.mapDefinition (rewriteTypes moduleResolver) (rewriteValues variables)
                            |> Result.map (Documented valueDef.value.doc)
                            |> Result.map (AccessControlled valueDef.access)
                            |> Result.map (Tuple.pair valueName)
                            |> Result.mapError List.concat
                    )
                |> ListOfResults.keepAllErrors
                |> Result.map Dict.fromList
                |> Result.mapError List.concat
    in
    Result.map3 Module.Definition
        typesResult
        valuesResult
        (Ok moduleDef.doc)


resolveVariablesAndReferences : Dict Name SourceLocation -> ModuleResolver -> Value SourceLocation SourceLocation -> Result Errors (Value SourceLocation SourceLocation)
resolveVariablesAndReferences variables moduleResolver value =
    let
        unionNames : (Name -> SourceLocation -> SourceLocation -> Error) -> Dict Name SourceLocation -> Dict Name SourceLocation -> Result Errors (Dict Name SourceLocation)
        unionNames toError namesA namesB =
            let
                duplicateNames : List Name
                duplicateNames =
                    Set.intersect (namesA |> Dict.keys |> Set.fromList) (namesB |> Dict.keys |> Set.fromList)
                        |> Set.toList
            in
            if List.isEmpty duplicateNames then
                Ok (Dict.union namesA namesB)

            else
                Err
                    (duplicateNames
                        |> List.filterMap
                            (\name ->
                                Maybe.map2 (toError name)
                                    (namesA |> Dict.get name)
                                    (namesB |> Dict.get name)
                            )
                    )

        unionPatternNames : Dict Name SourceLocation -> Dict Name SourceLocation -> Result Errors (Dict Name SourceLocation)
        unionPatternNames =
            unionNames DuplicateNameInPattern

        unionVariableNames : Dict Name SourceLocation -> Dict Name SourceLocation -> Result Errors (Dict Name SourceLocation)
        unionVariableNames =
            unionNames VariableShadowing

        namesBoundInPattern : Value.Pattern SourceLocation -> Result Errors (Dict Name SourceLocation)
        namesBoundInPattern pattern =
            case pattern of
                Value.AsPattern sourceLocation subjectPattern alias ->
                    namesBoundInPattern subjectPattern
                        |> Result.andThen
                            (\subjectNames ->
                                unionPatternNames subjectNames
                                    (Dict.singleton alias sourceLocation)
                            )

                Value.TuplePattern _ elems ->
                    elems
                        |> List.map namesBoundInPattern
                        |> List.foldl
                            (\nextNames soFar ->
                                soFar
                                    |> Result.andThen
                                        (\namesSoFar ->
                                            nextNames
                                                |> Result.andThen (unionPatternNames namesSoFar)
                                        )
                            )
                            (Ok Dict.empty)

                Value.ConstructorPattern _ _ args ->
                    args
                        |> List.map namesBoundInPattern
                        |> List.foldl
                            (\nextNames soFar ->
                                soFar
                                    |> Result.andThen
                                        (\namesSoFar ->
                                            nextNames
                                                |> Result.andThen (unionPatternNames namesSoFar)
                                        )
                            )
                            (Ok Dict.empty)

                Value.HeadTailPattern _ headPattern tailPattern ->
                    namesBoundInPattern headPattern
                        |> Result.andThen
                            (\headNames ->
                                namesBoundInPattern tailPattern
                                    |> Result.andThen (unionPatternNames headNames)
                            )

                _ ->
                    Ok Dict.empty

        resolveValueDefinition def variablesDefNamesAndArgs =
            Result.map3 Value.Definition
                (def.inputTypes
                    |> List.map
                        (\( argName, a, argType ) ->
                            rewriteTypes moduleResolver argType
                                |> Result.map (\t -> ( argName, a, t ))
                        )
                    |> ListOfResults.keepAllErrors
                    |> Result.mapError List.concat
                )
                (rewriteTypes moduleResolver def.outputType)
                (resolveVariablesAndReferences variablesDefNamesAndArgs moduleResolver def.body)
    in
    case value of
        Value.Constructor sourceLocation ( [], modulePath, localName ) ->
            moduleResolver.resolveCtor
                (modulePath |> List.map Name.toTitleCase)
                (localName |> Name.toTitleCase)
                |> Result.map
                    (\resolvedFullName ->
                        Value.Constructor sourceLocation resolvedFullName
                    )
                |> Result.mapError (ResolveError sourceLocation >> List.singleton)

        Value.Reference sourceLocation ( [], modulePath, localName ) ->
            if List.isEmpty modulePath && (variables |> Dict.member localName) then
                Ok (Value.Variable sourceLocation localName)

            else
                moduleResolver.resolveValue
                    (modulePath |> List.map Name.toTitleCase)
                    (localName |> Name.toCamelCase)
                    |> Result.map
                        (\resolvedFullName ->
                            Value.Reference sourceLocation resolvedFullName
                        )
                    |> Result.mapError (ResolveError sourceLocation >> List.singleton)

        Value.Lambda a argPattern bodyValue ->
            Result.map2 (Value.Lambda a)
                (resolvePatternReferences moduleResolver argPattern)
                (namesBoundInPattern argPattern
                    |> Result.andThen
                        (\patternNames ->
                            unionVariableNames variables patternNames
                        )
                    |> Result.andThen
                        (\newVariables ->
                            resolveVariablesAndReferences newVariables moduleResolver bodyValue
                        )
                )

        Value.LetDefinition sourceLocation name def inValue ->
            Result.map2 (Value.LetDefinition sourceLocation name)
                (def.inputTypes
                    |> List.map (\( argName, loc, _ ) -> ( argName, loc ))
                    |> Dict.fromList
                    |> Dict.insert name sourceLocation
                    |> unionVariableNames variables
                    |> Result.andThen (resolveValueDefinition def)
                )
                (unionVariableNames variables (Dict.singleton name sourceLocation)
                    |> Result.andThen
                        (\newVariables ->
                            resolveVariablesAndReferences newVariables moduleResolver inValue
                        )
                )

        Value.LetRecursion sourceLocation defs inValue ->
            defs
                |> Dict.map (\_ _ -> sourceLocation)
                |> unionVariableNames variables
                |> Result.andThen
                    (\variablesAndDefNames ->
                        Result.map2 (Value.LetRecursion sourceLocation)
                            (defs
                                |> Dict.toList
                                |> List.map
                                    (\( name, def ) ->
                                        def.inputTypes
                                            |> List.map (\( argName, loc, _ ) -> ( argName, loc ))
                                            |> Dict.fromList
                                            |> unionVariableNames variablesAndDefNames
                                            |> Result.andThen
                                                (\variablesDefNamesAndArgs ->
                                                    Result.map (Tuple.pair name)
                                                        (resolveValueDefinition def variablesDefNamesAndArgs)
                                                )
                                    )
                                |> ListOfResults.keepAllErrors
                                |> Result.mapError List.concat
                                |> Result.map Dict.fromList
                            )
                            (resolveVariablesAndReferences variablesAndDefNames moduleResolver inValue)
                    )

        Value.Destructure a pattern subjectValue inValue ->
            Result.map3 (Value.Destructure a)
                (resolvePatternReferences moduleResolver pattern)
                (resolveVariablesAndReferences variables moduleResolver subjectValue)
                (namesBoundInPattern pattern
                    |> Result.andThen
                        (\patternNames ->
                            unionVariableNames variables patternNames
                        )
                    |> Result.andThen
                        (\newVariables ->
                            resolveVariablesAndReferences newVariables moduleResolver inValue
                        )
                )

        Value.PatternMatch a matchValue cases ->
            Result.map2 (Value.PatternMatch a)
                (resolveVariablesAndReferences variables moduleResolver matchValue)
                (cases
                    |> List.map
                        (\( casePattern, caseValue ) ->
                            Result.map2 Tuple.pair
                                (resolvePatternReferences moduleResolver casePattern)
                                (namesBoundInPattern casePattern
                                    |> Result.andThen
                                        (\patternNames ->
                                            unionVariableNames variables patternNames
                                        )
                                    |> Result.andThen
                                        (\newVariables ->
                                            resolveVariablesAndReferences newVariables moduleResolver caseValue
                                        )
                                )
                        )
                    |> ListOfResults.keepAllErrors
                    |> Result.mapError List.concat
                )

        Value.Tuple a elems ->
            elems
                |> List.map (resolveVariablesAndReferences variables moduleResolver)
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.Tuple a)

        Value.List a items ->
            items
                |> List.map (resolveVariablesAndReferences variables moduleResolver)
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.List a)

        Value.Record a fields ->
            fields
                |> Dict.toList
                |> List.map
                    (\( fieldName, fieldValue ) ->
                        resolveVariablesAndReferences variables moduleResolver fieldValue
                            |> Result.map (Tuple.pair fieldName)
                    )
                |> ListOfResults.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Dict.fromList >> Value.Record a)

        Value.Field a subjectValue fieldName ->
            resolveVariablesAndReferences variables moduleResolver subjectValue
                |> Result.map (\s -> Value.Field a s fieldName)

        Value.Apply a funValue argValue ->
            Result.map2 (Value.Apply a)
                (resolveVariablesAndReferences variables moduleResolver funValue)
                (resolveVariablesAndReferences variables moduleResolver argValue)

        Value.IfThenElse a condValue thenValue elseValue ->
            Result.map3 (Value.IfThenElse a)
                (resolveVariablesAndReferences variables moduleResolver condValue)
                (resolveVariablesAndReferences variables moduleResolver thenValue)
                (resolveVariablesAndReferences variables moduleResolver elseValue)

        Value.UpdateRecord a subjectValue newFieldValues ->
            Result.map2 (Value.UpdateRecord a)
                (resolveVariablesAndReferences variables moduleResolver subjectValue)
                (newFieldValues
                    |> Dict.toList
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            resolveVariablesAndReferences variables moduleResolver fieldValue
                                |> Result.map (Tuple.pair fieldName)
                        )
                    |> ListOfResults.keepAllErrors
                    |> Result.mapError List.concat
                    |> Result.map Dict.fromList
                )

        _ ->
            Ok value


{-| Resolve references with local names into fully-qualified names. Currently this will only apply to
constructor patterns as they are the only ones with a reference to other names.
-}
resolvePatternReferences : ModuleResolver -> Value.Pattern SourceLocation -> Result Errors (Value.Pattern SourceLocation)
resolvePatternReferences moduleResolver pattern =
    case pattern of
        Value.AsPattern sourceLocation subjectPattern alias ->
            Result.map (\resolvedSubjectPattern -> Value.AsPattern sourceLocation resolvedSubjectPattern alias)
                (resolvePatternReferences moduleResolver subjectPattern)

        Value.TuplePattern sourceLocation elems ->
            Result.map (\resolvedElems -> Value.TuplePattern sourceLocation resolvedElems)
                (elems
                    |> List.map (resolvePatternReferences moduleResolver)
                    |> ListOfResults.keepAllErrors
                    |> Result.mapError List.concat
                )

        Value.ConstructorPattern sourceLocation ( [], modulePath, localName ) argPatterns ->
            Result.map2
                (\resolvedFullName resolvedArgPatterns ->
                    Value.ConstructorPattern sourceLocation resolvedFullName resolvedArgPatterns
                )
                (moduleResolver.resolveCtor
                    (modulePath |> List.map Name.toTitleCase)
                    (localName |> Name.toTitleCase)
                    |> Result.mapError (ResolveError sourceLocation >> List.singleton)
                )
                (argPatterns
                    |> List.map (resolvePatternReferences moduleResolver)
                    |> ListOfResults.keepAllErrors
                    |> Result.mapError List.concat
                )

        Value.HeadTailPattern sourceLocation headPattern tailPattern ->
            Result.map2 (Value.HeadTailPattern sourceLocation)
                (resolvePatternReferences moduleResolver headPattern)
                (resolvePatternReferences moduleResolver tailPattern)

        _ ->
            Ok pattern


withAccessControl : Bool -> a -> AccessControlled a
withAccessControl isExposed a =
    if isExposed then
        public a

    else
        private a


withWellKnownOperators : ProcessContext -> ProcessContext
withWellKnownOperators context =
    List.foldl Processing.addDependency context WellKnownOperators.wellKnownOperators
