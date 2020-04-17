module Morphir.Elm.Frontend exposing (ContentLocation, ContentRange, Error(..), Errors, PackageInfo, SourceFile, SourceLocation, decodePackageInfo, encodeError, mapDeclarationsToType, packageDefinitionFromSource)

import Dict exposing (Dict)
import Elm.Parser
import Elm.Processing as Processing
import Elm.RawFile as RawFile exposing (RawFile)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Exposing as Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression exposing (Expression, Function, FunctionImplementation)
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Module as ElmModule
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern(..))
import Elm.Syntax.Range exposing (Range)
import Elm.Syntax.TypeAnnotation exposing (TypeAnnotation(..))
import Graph exposing (Graph)
import Json.Decode as Decode
import Json.Encode as Encode
import Morphir.Elm.Frontend.Resolve as Resolve exposing (ModuleResolver, PackageResolver)
import Morphir.Graph
import Morphir.IR.AccessControlled exposing (AccessControlled, private, public)
import Morphir.IR.FQName as FQName exposing (FQName, fQName)
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK as SDK
import Morphir.IR.SDK.Appending as Appending
import Morphir.IR.SDK.Bool as Bool
import Morphir.IR.SDK.Comparison as Comparison
import Morphir.IR.SDK.Composition as Composition
import Morphir.IR.SDK.Equality as Equality
import Morphir.IR.SDK.Float as Float
import Morphir.IR.SDK.Int as Int
import Morphir.IR.SDK.List as List
import Morphir.IR.SDK.Number as Number
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.JsonExtra as JsonExtra
import Morphir.ListOfResults as ListOfResults
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


encodeSourceFile : SourceFile -> Encode.Value
encodeSourceFile sourceFile =
    Encode.object
        [ ( "path", Encode.string sourceFile.path ) ]


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


encodeSourceLocation : SourceLocation -> Encode.Value
encodeSourceLocation sourceLocation =
    Encode.object
        [ ( "source", encodeSourceFile sourceLocation.source )
        , ( "range", encodeContentRange sourceLocation.range )
        ]


type alias ContentRange =
    { start : ContentLocation
    , end : ContentLocation
    }


encodeContentRange : ContentRange -> Encode.Value
encodeContentRange contentRange =
    Encode.object
        [ ( "start", encodeContentLocation contentRange.start )
        , ( "end", encodeContentLocation contentRange.end )
        ]


type alias ContentLocation =
    { row : Int
    , column : Int
    }


encodeContentLocation : ContentLocation -> Encode.Value
encodeContentLocation contentLocation =
    Encode.object
        [ ( "row", Encode.int contentLocation.row )
        , ( "column", Encode.int contentLocation.column )
        ]


type alias Errors =
    List Error


type Error
    = ParseError String (List Parser.DeadEnd)
    | CyclicModules (Morphir.Graph.Graph () (List String))
    | ResolveError SourceLocation Resolve.Error
    | EmptyApply SourceLocation
    | NotSupported SourceLocation String


encodeError : Error -> Encode.Value
encodeError error =
    case error of
        ParseError _ _ ->
            JsonExtra.encodeConstructor "ParseError" []

        CyclicModules _ ->
            JsonExtra.encodeConstructor "CyclicModules" []

        ResolveError sourceLocation resolveError ->
            JsonExtra.encodeConstructor "ResolveError"
                [ encodeSourceLocation sourceLocation
                , Resolve.encodeError resolveError
                ]

        EmptyApply sourceLocation ->
            JsonExtra.encodeConstructor "EmptyApply"
                [ encodeSourceLocation sourceLocation
                ]

        NotSupported sourceLocation message ->
            JsonExtra.encodeConstructor "NotSupported"
                [ encodeSourceLocation sourceLocation
                , Encode.string message
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
                |> ListOfResults.toResult

        exposedModuleNames : Set ModuleName
        exposedModuleNames =
            packageInfo.exposedModules
                |> Set.map
                    (\modulePath ->
                        (packageInfo.name |> Path.toList)
                            ++ (modulePath |> Path.toList)
                            |> List.map Name.toTitleCase
                    )

        treeShakeModules : List ( ModuleName, ParsedFile ) -> List ( ModuleName, ParsedFile )
        treeShakeModules allModules =
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
                parsedFiles
                    |> treeShakeModules
                    |> sortModules
                    |> Result.andThen (mapParsedFiles packageInfo.name parsedFilesByModuleName)
            )
        |> Result.map
            (\moduleDefs ->
                { dependencies = Dict.empty
                , modules =
                    moduleDefs
                        |> Dict.toList
                        |> List.map
                            (\( modulePath, m ) ->
                                let
                                    packageLessModulePath =
                                        modulePath
                                            |> Path.toList
                                            |> List.drop (packageInfo.name |> Path.toList |> List.length)
                                            |> Path.fromList
                                in
                                if packageInfo.exposedModules |> Set.member packageLessModulePath then
                                    ( packageLessModulePath, public m )

                                else
                                    ( packageLessModulePath, private m )
                            )
                        |> Dict.fromList
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

        moduleDeclsSoFar =
            modulesSoFar
                |> Dict.map
                    (\_ def ->
                        Module.definitionToSpecification def
                            |> Module.eraseSpecificationAttributes
                    )

        dependencies =
            Dict.fromList
                [ ( SDK.packageName, SDK.packageSpec )
                ]

        moduleResolver : ModuleResolver
        moduleResolver =
            Resolve.createModuleResolver
                (Resolve.createPackageResolver dependencies currentPackagePath moduleDeclsSoFar)
                (processedFile.file.imports |> List.map Node.value)

        typesResult : Result Errors (Dict Name (AccessControlled (Type.Definition SourceLocation)))
        typesResult =
            mapDeclarationsToType processedFile.parsedFile.sourceFile moduleExpose (processedFile.file.declarations |> List.map Node.value)
                |> Result.map Dict.fromList

        valuesResult : Result Errors (Dict Name (AccessControlled (Value.Definition SourceLocation)))
        valuesResult =
            mapDeclarationsToValue processedFile.parsedFile.sourceFile moduleExpose (processedFile.file.declarations |> List.map Node.value)
                |> Result.map Dict.fromList

        moduleResult : Result Errors (Module.Definition SourceLocation)
        moduleResult =
            Result.map2 Module.Definition
                typesResult
                valuesResult
    in
    moduleResult
        |> Result.andThen (resolveLocalNames currentPackagePath modulePath moduleResolver)
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
                                                        |> ListOfResults.toResult
                                                        |> Result.mapError List.concat
                                            in
                                            ctorArgsResult
                                                |> Result.map
                                                    (\ctorArgs ->
                                                        Type.Constructor ctorName ctorArgs
                                                    )
                                        )
                                    |> ListOfResults.toResult
                                    |> Result.mapError List.concat
                        in
                        ctorsResult
                            |> Result.map
                                (\constructors ->
                                    ( name, withAccessControl isTypeExposed (Type.customTypeDefinition typeParams (withAccessControl isCtorExposed constructors)) )
                                )
                            |> Just

                    _ ->
                        Nothing
            )
        |> ListOfResults.toResult
        |> Result.mapError List.concat


mapDeclarationsToValue : SourceFile -> Exposing -> List Declaration -> Result Errors (List ( Name, AccessControlled (Value.Definition SourceLocation) ))
mapDeclarationsToValue sourceFile expose decls =
    decls
        |> List.filterMap
            (\decl ->
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

                            valueDef : Result Errors (AccessControlled (Value.Definition SourceLocation))
                            valueDef =
                                function
                                    |> mapFunction sourceFile
                                    |> Result.map public
                        in
                        valueDef
                            |> Result.map (Tuple.pair valueName)
                            |> Just

                    _ ->
                        Nothing
            )
        |> ListOfResults.toResult
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
                    |> ListOfResults.toResult
                    |> Result.mapError List.concat
                )

        Unit ->
            Ok (Type.Unit sourceLocation)

        Tupled elemNodes ->
            elemNodes
                |> List.map (mapTypeAnnotation sourceFile)
                |> ListOfResults.toResult
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
                |> ListOfResults.toResult
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
                |> ListOfResults.toResult
                |> Result.map (Type.ExtensibleRecord sourceLocation (argName |> Name.fromString))
                |> Result.mapError List.concat

        FunctionTypeAnnotation argTypeNode returnTypeNode ->
            Result.map2 (Type.Function sourceLocation)
                (mapTypeAnnotation sourceFile argTypeNode)
                (mapTypeAnnotation sourceFile returnTypeNode)


mapFunction : SourceFile -> Function -> Result Errors (Value.Definition SourceLocation)
mapFunction sourceFile function =
    function.declaration
        |> Node.value
        |> (\funImpl ->
                mapFunctionImplementation sourceFile funImpl.arguments funImpl.expression
           )


mapFunctionImplementation : SourceFile -> List (Node Pattern) -> Node Expression -> Result Errors (Value.Definition SourceLocation)
mapFunctionImplementation sourceFile argumentNodes expression =
    let
        sourceLocation : Range -> SourceLocation
        sourceLocation range =
            range |> SourceLocation sourceFile

        extractNamedParams : List Name -> List (Node Pattern) -> ( List Name, List (Node Pattern) )
        extractNamedParams namedParams patternParams =
            case patternParams of
                [] ->
                    ( namedParams, patternParams )

                (Node _ firstParam) :: restOfParams ->
                    case firstParam of
                        VarPattern paramName ->
                            extractNamedParams (namedParams ++ [ Name.fromString paramName ]) restOfParams

                        _ ->
                            ( namedParams, patternParams )

        ( paramNames, lambdaArgPatterns ) =
            extractNamedParams [] argumentNodes

        bodyResult : Result Errors (Value.Value SourceLocation)
        bodyResult =
            let
                lambdaWithParams : List (Node Pattern) -> Node Expression -> Result Errors (Value.Value SourceLocation)
                lambdaWithParams params body =
                    case params of
                        [] ->
                            mapExpression sourceFile body

                        (Node range firstParam) :: restOfParams ->
                            Result.map2 (\lambdaArg lambdaBody -> Value.Lambda (sourceLocation range) lambdaArg lambdaBody)
                                (mapPattern sourceFile (Node range firstParam))
                                (lambdaWithParams restOfParams body)
            in
            lambdaWithParams lambdaArgPatterns expression
    in
    bodyResult
        |> Result.map (Value.UntypedDefinition paramNames)


mapExpression : SourceFile -> Node Expression -> Result Errors (Value.Value SourceLocation)
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
                toApply : List (Value.Value SourceLocation) -> Result Errors (Value.Value SourceLocation)
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
                |> ListOfResults.toResult
                |> Result.mapError List.concat
                |> Result.andThen (List.reverse >> toApply)

        Expression.OperatorApplication op _ leftNode rightNode ->
            mapOperator sourceFile sourceLocation op leftNode rightNode

        Expression.FunctionOrValue moduleName valueName ->
            case ( moduleName, valueName ) of
                ( [], "True" ) ->
                    Ok (Value.Literal sourceLocation (Value.BoolLiteral True))

                ( [], "False" ) ->
                    Ok (Value.Literal sourceLocation (Value.BoolLiteral False))

                _ ->
                    Ok (Value.Reference sourceLocation (fQName [] (moduleName |> List.map Name.fromString) (valueName |> Name.fromString)))

        Expression.IfBlock condNode thenNode elseNode ->
            Result.map3 (Value.IfThenElse sourceLocation)
                (mapExpression sourceFile condNode)
                (mapExpression sourceFile thenNode)
                (mapExpression sourceFile elseNode)

        Expression.PrefixOperator _ ->
            Err [ NotSupported sourceLocation "TODO: PrefixOperator" ]

        Expression.Operator _ ->
            Err [ NotSupported sourceLocation "TODO: Operator" ]

        Expression.Integer value ->
            Ok (Value.Literal sourceLocation (Value.IntLiteral value))

        Expression.Hex value ->
            Ok (Value.Literal sourceLocation (Value.IntLiteral value))

        Expression.Floatable value ->
            Ok (Value.Literal sourceLocation (Value.FloatLiteral value))

        Expression.Negation arg ->
            mapExpression sourceFile arg
                |> Result.map (Number.negate sourceLocation sourceLocation)

        Expression.Literal value ->
            Ok (Value.Literal sourceLocation (Value.StringLiteral value))

        Expression.CharLiteral value ->
            Ok (Value.Literal sourceLocation (Value.CharLiteral value))

        Expression.TupledExpression expNodes ->
            expNodes
                |> List.map (mapExpression sourceFile)
                |> ListOfResults.toResult
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
                    |> ListOfResults.toResult
                    |> Result.mapError List.concat
                )

        Expression.LambdaExpression lambda ->
            let
                curriedLambda : List (Node Pattern) -> Node Expression -> Result Errors (Value.Value SourceLocation)
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
                |> ListOfResults.toResult
                |> Result.mapError List.concat
                |> Result.map (Value.Record sourceLocation)

        Expression.ListExpr itemNodes ->
            itemNodes
                |> List.map (mapExpression sourceFile)
                |> ListOfResults.toResult
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
                |> ListOfResults.toResult
                |> Result.mapError List.concat
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
            Ok (Value.LiteralPattern sourceLocation (Value.CharLiteral char))

        Pattern.StringPattern string ->
            Ok (Value.LiteralPattern sourceLocation (Value.StringLiteral string))

        Pattern.IntPattern int ->
            Ok (Value.LiteralPattern sourceLocation (Value.IntLiteral int))

        Pattern.HexPattern int ->
            Ok (Value.LiteralPattern sourceLocation (Value.IntLiteral int))

        Pattern.FloatPattern float ->
            Ok (Value.LiteralPattern sourceLocation (Value.FloatLiteral float))

        Pattern.TuplePattern elemNodes ->
            elemNodes
                |> List.map (mapPattern sourceFile)
                |> ListOfResults.toResult
                |> Result.mapError List.concat
                |> Result.map (Value.TuplePattern sourceLocation)

        Pattern.RecordPattern fieldNameNodes ->
            Ok
                (Value.RecordPattern sourceLocation
                    (fieldNameNodes
                        |> List.map (Node.value >> Name.fromString)
                    )
                )

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
            argNodes
                |> List.map (mapPattern sourceFile)
                |> ListOfResults.toResult
                |> Result.mapError List.concat
                |> Result.map (Value.ConstructorPattern sourceLocation qualifiedName)

        Pattern.AsPattern subjectNode aliasNode ->
            mapPattern sourceFile subjectNode
                |> Result.map (\subject -> Value.AsPattern sourceLocation subject (aliasNode |> Node.value |> Name.fromString))

        Pattern.ParenthesizedPattern childNode ->
            mapPattern sourceFile childNode


mapOperator : SourceFile -> SourceLocation -> String -> Node Expression -> Node Expression -> Result Errors (Value.Value SourceLocation)
mapOperator sourceFile sourceLocation op leftNode rightNode =
    let
        applyBinary : (SourceLocation -> Value SourceLocation -> Value SourceLocation -> Value SourceLocation) -> Result Errors (Value.Value SourceLocation)
        applyBinary fun =
            Result.map2 (fun sourceLocation)
                (mapExpression sourceFile leftNode)
                (mapExpression sourceFile rightNode)
    in
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

        "||" ->
            applyBinary Bool.or

        "&&" ->
            applyBinary Bool.and

        "==" ->
            applyBinary Equality.equal

        "/=" ->
            applyBinary Equality.notEqual

        "<" ->
            applyBinary Comparison.lessThan

        ">" ->
            applyBinary Comparison.greaterThan

        "<=" ->
            applyBinary Comparison.lessThanOrEqual

        ">=" ->
            applyBinary Comparison.greaterThanOrEqual

        "++" ->
            applyBinary Appending.append

        "+" ->
            applyBinary Number.add

        "-" ->
            applyBinary Number.subtract

        "*" ->
            applyBinary Number.multiply

        "/" ->
            applyBinary Float.divide

        "//" ->
            applyBinary Int.divide

        "^" ->
            applyBinary Number.power

        "<<" ->
            applyBinary Composition.composeLeft

        ">>" ->
            applyBinary Composition.composeRight

        "::" ->
            applyBinary List.construct

        _ ->
            Err [ NotSupported sourceLocation <| "OperatorApplication: " ++ op ]


mapLetExpression : SourceFile -> SourceLocation -> Expression.LetBlock -> Result Errors (Value SourceLocation)
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

        letBlockToValue : List (Node Expression.LetDeclaration) -> Node Expression -> Result Errors (Value.Value SourceLocation)
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

                letDeclarationToValue : Node Expression.LetDeclaration -> Result Errors (Value.Value SourceLocation) -> Result Errors (Value.Value SourceLocation)
                letDeclarationToValue letDeclarationNode valueResult =
                    case letDeclarationNode |> Node.value of
                        Expression.LetFunction function ->
                            Result.map2 (Value.LetDefinition sourceLocation (function.declaration |> Node.value |> .name |> Node.value |> Name.fromString))
                                (mapFunction sourceFile function)
                                valueResult

                        Expression.LetDestructuring patternNode letExpressionNode ->
                            Result.map3 (Value.Destructure sourceLocation)
                                (mapPattern sourceFile patternNode)
                                (mapExpression sourceFile letExpressionNode)
                                valueResult

                componentGraphToValue : Graph (Node Expression.LetDeclaration) String -> Result Errors (Value.Value SourceLocation) -> Result Errors (Value.Value SourceLocation)
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
                                            case graphNode.label |> Node.value of
                                                Expression.LetFunction function ->
                                                    mapFunction sourceFile function
                                                        |> Result.map (Tuple.pair (function.declaration |> Node.value |> .name |> Node.value |> Name.fromString))

                                                Expression.LetDestructuring _ _ ->
                                                    Err [ NotSupported sourceLocation "Recursive destructuring" ]
                                        )
                                    |> ListOfResults.toResult
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


resolveLocalNames : Path -> Path -> ModuleResolver -> Module.Definition SourceLocation -> Result Errors (Module.Definition SourceLocation)
resolveLocalNames packagePath modulePath moduleResolver moduleDef =
    let
        rewriteTypes : Type SourceLocation -> Result Error (Type SourceLocation)
        rewriteTypes =
            Rewrite.bottomUp Type.rewriteType
                (\tpe ->
                    case tpe of
                        Type.Reference sourceLocation refFullName args ->
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
                                        Type.Reference sourceLocation resolvedFullName args
                                    )
                                |> Result.mapError (ResolveError sourceLocation)
                                |> Just

                        _ ->
                            Nothing
                )

        rewriteValues : Value SourceLocation -> Result Error (Value SourceLocation)
        rewriteValues value =
            Ok value
    in
    Module.mapDefinition rewriteTypes rewriteValues moduleDef


withAccessControl : Bool -> a -> AccessControlled a
withAccessControl isExposed a =
    if isExposed then
        public a

    else
        private a
