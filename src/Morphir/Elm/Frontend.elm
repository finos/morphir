module Morphir.Elm.Frontend exposing (Error(..), Errors, PackageInfo, SourceFile, SourceLocation, decodePackageInfo, encodeError, packageDefinitionFromSource)

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
import Elm.Syntax.TypeAnnotation exposing (TypeAnnotation(..))
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.DAG as DAG exposing (DAG)
import Morphir.Elm.Frontend.Resolve as Resolve exposing (ModuleResolver, PackageResolver)
import Morphir.IR.AccessControlled as AccessControlled exposing (AccessControlled, private, public)
import Morphir.IR.Advanced.Module as Module
import Morphir.IR.Advanced.Package as Package
import Morphir.IR.Advanced.Type as Type exposing (Type)
import Morphir.IR.Advanced.Value as Value exposing (Value)
import Morphir.IR.FQName as FQName exposing (FQName, fQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.ResultList as ResultList
import Morphir.Rewrite as Rewrite
import Parser
import Set exposing (Set)


type alias PackageInfo =
    { name : Path
    , exposedModules : Set Path
    }


decodePackageInfo : Decode.Decoder PackageInfo
decodePackageInfo =
    Decode.map2 PackageInfo
        (Decode.field "name"
            (Decode.string
                |> Decode.map Path.fromString
            )
        )
        (Decode.field "exposedModules"
            (Decode.list (Decode.string |> Decode.map Path.fromString)
                |> Decode.map Set.fromList
            )
        )


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


encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ParseError _ _ ->
            Encode.object
                [ ( "$type", Encode.string "ParseError" )
                ]

        CyclicModules _ ->
            Encode.object
                [ ( "$type", Encode.string "CyclicModules" )
                ]

        ResolveError _ ->
            Encode.object
                [ ( "$type", Encode.string "ResolveError" )
                ]


type alias Imports =
    { lookupByExposedCtor : String -> Maybe Import
    , byModuleName : Dict ModuleName Import
    }


type alias Import =
    { packagePath : Path
    , modulePath : Path
    , exposesCtor : String -> Bool
    }


packageDefinitionFromSource : PackageInfo -> List SourceFile -> Result Errors (Package.Definition SourceLocation)
packageDefinitionFromSource packageInfo sourceFiles =
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
                    |> Result.andThen (mapParsedFiles packageInfo.name parsedFilesByModuleName)
            )
        |> Result.map
            (\moduleDefs ->
                { dependencies = Dict.empty
                , modules =
                    moduleDefs
                        |> Dict.map
                            (\modulePath m ->
                                if packageInfo.exposedModules |> Set.member modulePath then
                                    public m

                                else
                                    private m
                            )
                }
            )


mapParsedFiles : Path -> Dict ModuleName ParsedFile -> List ModuleName -> Result Errors (Dict Path (Module.Definition SourceLocation))
mapParsedFiles currentPackagePath parsedModules sortedModuleNames =
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
                            mapProcessedFile currentPackagePath processedFile modulesSoFar
                        )
            )
            (Ok Dict.empty)


mapProcessedFile : Path -> ProcessedFile -> Dict Path (Module.Definition SourceLocation) -> Result Errors (Dict Path (Module.Definition SourceLocation))
mapProcessedFile currentPackagePath processedFile modulesSoFar =
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

        typesResult : Result Errors (Dict Name (AccessControlled (Type.Definition SourceLocation)))
        typesResult =
            mapDeclarationsToType processedFile.parsedFile.sourceFile moduleExpose (processedFile.file.declarations |> List.map Node.value)
                |> Result.map Dict.fromList

        valuesResult : Result Errors (Dict Name (AccessControlled (Value.Definition SourceLocation)))
        valuesResult =
            Ok Dict.empty

        moduleResult : Result Errors (Module.Definition SourceLocation)
        moduleResult =
            Result.map2 Module.Definition
                typesResult
                valuesResult
    in
    moduleResult
        |> Result.andThen (resolveLocalTypes currentPackagePath modulePath moduleResolver)
        |> Result.map
            (\m ->
                modulesSoFar
                    |> Dict.insert modulePath m
            )


mapDeclarationsToType : SourceFile -> Exposing -> List Declaration -> Result Errors (List ( Name, AccessControlled (Type.Definition SourceLocation) ))
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
                                    in
                                    ( name, withAccessControl isExposed (Type.typeAliasDefinition typeParams typeExp) )
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
                                                        |> ResultList.toResult
                                                        |> Result.mapError List.concat
                                            in
                                            ctorArgsResult
                                                |> Result.map
                                                    (\ctorArgs ->
                                                        ( ctorName, ctorArgs )
                                                    )
                                        )
                                    |> ResultList.toResult
                                    |> Result.mapError List.concat
                        in
                        ctorsResult
                            |> Result.map
                                (\ctors ->
                                    ( name, withAccessControl isTypeExposed (Type.customTypeDefinition typeParams (withAccessControl isCtorExposed ctors)) )
                                )
                            |> Just

                    _ ->
                        Nothing
            )
        |> ResultList.toResult
        |> Result.mapError List.concat


mapTypeAnnotation : SourceFile -> Node TypeAnnotation -> Result Errors (Type SourceLocation)
mapTypeAnnotation sourceFile (Node range typeAnnotation) =
    let
        sourceLocation =
            range |> SourceLocation sourceFile
    in
    case typeAnnotation of
        GenericType varName ->
            Ok (Type.variable (varName |> Name.fromString) sourceLocation)

        Typed (Node _ ( moduleName, localName )) argNodes ->
            Result.map
                (\args ->
                    Type.reference (fQName [] (moduleName |> List.map Name.fromString) (Name.fromString localName)) args sourceLocation
                )
                (argNodes
                    |> List.map (mapTypeAnnotation sourceFile)
                    |> ResultList.toResult
                    |> Result.mapError List.concat
                )

        Unit ->
            Ok (Type.unit sourceLocation)

        Tupled elemNodes ->
            elemNodes
                |> List.map (mapTypeAnnotation sourceFile)
                |> ResultList.toResult
                |> Result.map (\elemTypes -> Type.tuple elemTypes sourceLocation)
                |> Result.mapError List.concat

        Record fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldTypeNode ) ->
                        mapTypeAnnotation sourceFile fieldTypeNode
                            |> Result.map (Type.Field (fieldName |> Name.fromString))
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
                        mapTypeAnnotation sourceFile fieldTypeNode
                            |> Result.map (Type.Field (fieldName |> Name.fromString))
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
                (mapTypeAnnotation sourceFile argTypeNode)
                (mapTypeAnnotation sourceFile returnTypeNode)


resolveLocalTypes : Path -> Path -> ModuleResolver -> Module.Definition SourceLocation -> Result Errors (Module.Definition SourceLocation)
resolveLocalTypes packagePath modulePath moduleResolver moduleDef =
    let
        rewriteTypes : Type SourceLocation -> Result Error (Type SourceLocation)
        rewriteTypes =
            Rewrite.bottomUp Type.rewriteType
                (\tpe ->
                    case tpe of
                        Type.Reference refFullName args sourceLocation ->
                            let
                                refModulePath : Path
                                refModulePath =
                                    refFullName
                                        |> FQName.getModulePath

                                refLocalName : Name
                                refLocalName =
                                    refFullName
                                        |> FQName.getLocalName

                                resolvedFullNameResult : Result Resolve.Error FQName
                                resolvedFullNameResult =
                                    case moduleDef.types |> Dict.get refLocalName of
                                        Just _ ->
                                            if Path.isPrefixOf modulePath packagePath then
                                                Ok (fQName packagePath (modulePath |> List.drop (List.length packagePath)) refLocalName)

                                            else
                                                Err (Resolve.PackageNotPrefixOfModule packagePath modulePath)

                                        Nothing ->
                                            moduleResolver.resolveType (refModulePath |> List.map Name.toTitleCase) (refLocalName |> Name.toTitleCase)
                            in
                            resolvedFullNameResult
                                |> Result.map
                                    (\resolvedFullName ->
                                        Type.Reference resolvedFullName args sourceLocation
                                    )
                                |> Result.mapError ResolveError
                                |> Just

                        _ ->
                            Nothing
                )

        rewriteValues =
            identity
    in
    Module.mapDefinition rewriteTypes rewriteValues moduleDef


withAccessControl : Bool -> a -> AccessControlled a
withAccessControl isExposed a =
    if isExposed then
        public a

    else
        private a
