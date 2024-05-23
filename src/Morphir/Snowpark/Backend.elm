module Morphir.Snowpark.Backend exposing (Options, decodeOptions, mapDistribution, mapFunctionDefinition)

import Dict
import Json.Decode as Decode exposing (Decoder)
import List
import List.Extra
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Decoration.Codec exposing (decodeNodeIDByValuePairs)
import Morphir.IR.Distribution as Distribution exposing (..)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module
import Morphir.IR.Name as Name
import Morphir.IR.NodeId exposing (NodeID)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.SDK.Dict as SDKDict
import Morphir.Scala.AST as Scala
import Morphir.Scala.Common exposing (javaObjectMethods, mapValueName, scalaKeywords)
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.Snowpark.Constants exposing (typeRefForSnowparkType)
import Morphir.Snowpark.Customization
    exposing
        ( CustomizationOptions
        , emptyCustomizationOptions
        , loadCustomizationOptions
        , tryToApplyPostConversionCustomization
        )
import Morphir.Snowpark.FunctionMappingsForPlainScala as FunctionMappingsForPlainScala
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue, GenerationIssues, createGenerationReport)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)
import Morphir.Snowpark.MappingContext as MappingContext
    exposing
        ( FunctionClassification(..)
        , GlobalDefinitionInformation
        , MappingContextInfo
        , ValueMappingContext
        , emptyValueMappingContext
        , getFunctionClassification
        , isCandidateForDataFrame
        )
import Morphir.Snowpark.RecordWrapperGenerator as RecordWrapperGenerator
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord)
import Morphir.Snowpark.TypeRefMapping exposing (mapFunctionReturnType, mapTypeReference)
import Set as Set


{-| Generate Scala files that use the Snowpark API to process DataFrame-like structures.
-}
type alias Options =
    { decorations : Maybe (SDKDict.Dict NodeID Decode.Value) }


decodeOptions : Decoder Options
decodeOptions =
    Decode.map Options
        (Decode.maybe
            (Decode.field "decorationsObj" decodeNodeIDByValuePairs)
        )


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opts distro =
    let
        loadedOpts : CustomizationOptions
        loadedOpts =
            opts.decorations
                |> Maybe.map loadCustomizationOptions
                |> Maybe.withDefault emptyCustomizationOptions
    in
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition distro packageName packageDef loadedOpts


mapPackageDefinition : Distribution -> Package.PackageName -> Package.Definition () (Type ()) -> CustomizationOptions -> FileMap
mapPackageDefinition _ packagePath packageDef customizationOptions =
    let
        contextInfo =
            MappingContext.processDistributionModules packagePath packageDef customizationOptions

        ( generatedScala, issuesCollections ) =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( modulePath, moduleImpl ) ->
                        mapModuleDefinition packagePath modulePath moduleImpl contextInfo customizationOptions
                    )
                |> List.unzip

        generatedFiles =
            generatedScala
                |> List.map
                    (\compilationUnit ->
                        let
                            fileContent =
                                compilationUnit
                                    |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                        in
                        ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
                    )
                |> Dict.fromList

        issues =
            issuesCollections
                |> List.foldr Dict.union Dict.empty
    in
    Dict.insert ( [], "GenerationReport.md" ) (createGenerationReport contextInfo customizationOptions issues) generatedFiles


mapModuleDefinition :
    Package.PackageName
    -> Path
    -> AccessControlled (Module.Definition () (Type ()))
    -> GlobalDefinitionInformation ()
    -> CustomizationOptions
    -> List ( Scala.CompilationUnit, GenerationIssues )
mapModuleDefinition currentPackagePath currentModulePath accessControlledModuleDef ctxInfo customizationOptions =
    let
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    let
                        parts =
                            List.append currentPackagePath (List.reverse reverseModulePath)
                    in
                    ( parts |> List.map (Name.toCamelCase >> String.toLower), lastName )

        moduleTypeDefinitions : List (Scala.Annotated Scala.MemberDecl)
        moduleTypeDefinitions =
            accessControlledModuleDef.value.types
                |> RecordWrapperGenerator.generateRecordWrappers currentPackagePath currentModulePath ctxInfo
                |> List.map (\doc -> { annotations = doc.value.annotations, value = Scala.MemberTypeDecl doc.value.value })

        ( functionMembers, generatedImports, membersIssues ) =
            accessControlledModuleDef.value.values
                |> Dict.toList
                |> List.map
                    (\( valueName, accessControlledValueDef ) ->
                        processFunctionMember valueName accessControlledValueDef currentPackagePath currentModulePath ctxInfo customizationOptions
                    )
                |> (\res ->
                        ( res |> List.map (\( t, _, _ ) -> t) |> List.concat |> List.map Scala.withoutAnnotation
                        , res |> List.map (\( _, t, _ ) -> t) |> List.concat
                        , res |> List.map (\( _, _, t ) -> t) |> List.foldr Dict.union Dict.empty
                        )
                   )

        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = generatedImports |> List.Extra.uniqueBy .packagePrefix
            , typeDecls =
                [ Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Scala.Annotated []
                        (Scala.Object
                            { modifiers =
                                []
                            , name =
                                moduleName |> Name.toTitleCase
                            , members =
                                moduleTypeDefinitions ++ functionMembers
                            , extends =
                                []
                            , body = Nothing
                            }
                        )
                    )
                ]
            }
    in
    [ ( moduleUnit, membersIssues ) ]


processFunctionMember :
    Name.Name
    -> AccessControlled (Documented (Value.Definition () (Type ())))
    -> Package.PackageName
    -> Path
    -> GlobalDefinitionInformation ()
    -> CustomizationOptions
    -> ( List Scala.MemberDecl, List Scala.ImportDecl, GenerationIssues )
processFunctionMember valueName accessControlledValueDef currentPackagePath currentModulePath ctxInfo customizationOptions =
    let
        fullFunctionName =
            FQName.fQName currentPackagePath currentModulePath valueName

        ( mappedFunction, issues ) =
            mapFunctionDefinition valueName accessControlledValueDef currentPackagePath currentModulePath ctxInfo

        issuesDict =
            if List.isEmpty issues then
                Dict.empty

            else
                Dict.insert fullFunctionName issues Dict.empty
    in
    case tryToApplyPostConversionCustomization fullFunctionName mappedFunction customizationOptions of
        Just ( mapped, imports ) ->
            ( mapped, imports, issuesDict )

        _ ->
            ( [ mappedFunction ], [], issuesDict )


mapFunctionDefinition : Name.Name -> AccessControlled (Documented (Value.Definition () (Type ()))) -> Path -> Path -> GlobalDefinitionInformation () -> ( Scala.MemberDecl, List GenerationIssue )
mapFunctionDefinition functionName body currentPackagePath modulePath ( typeContextInfo, functionsInfo, inlineInfo ) =
    let
        fullFunctionName =
            FQName.fQName currentPackagePath modulePath functionName

        functionClassification =
            getFunctionClassification fullFunctionName functionsInfo

        parameters =
            processParameters body.value.value.inputTypes functionClassification typeContextInfo

        parameterNames =
            body.value.value.inputTypes |> List.map (\( name, _, _ ) -> name)

        valueMappingContext =
            { emptyValueMappingContext
                | typesContextInfo = typeContextInfo
                , parameters = parameterNames
                , functionClassificationInfo = functionsInfo
                , currentFunctionClassification = functionClassification
                , packagePath = currentPackagePath
                , globalValuesToInline = inlineInfo
            }

        localDeclarations =
            body.value.value.inputTypes
                |> List.filterMap (checkForDataFrameColumndsDeclaration typeContextInfo)

        ( bodyCandidate, issues ) =
            mapFunctionBody body.value.value (includeDataFrameInfo localDeclarations valueMappingContext)

        returnTypeToGenerate =
            mapFunctionReturnType body.value.value.outputType functionClassification typeContextInfo

        resultingFunction =
            Scala.FunctionDecl
                { modifiers = []
                , name = mapValueName functionName
                , typeArgs = []
                , args = addImplicitSession parameters
                , returnType =
                    Just returnTypeToGenerate
                , body =
                    case ( localDeclarations |> List.map Tuple.first, bodyCandidate ) of
                        ( [], bodyToUse ) ->
                            Just bodyToUse

                        ( declarations, bodyToUse ) ->
                            Just (Scala.Block declarations bodyToUse)
                }
    in
    ( resultingFunction, issues )


addImplicitSession : List (List Scala.ArgDecl) -> List (List Scala.ArgDecl)
addImplicitSession args =
    case args of
        [] ->
            args

        _ ->
            let
                implicitArg =
                    { modifiers = [ Scala.Implicit ]
                    , tpe = typeRefForSnowparkType "Session"
                    , name = "sfSession"
                    , defaultValue = Nothing
                    }
            in
            args ++ [ [ implicitArg ] ]


includeDataFrameInfo : List ( Scala.MemberDecl, ( String, FQName.FQName ) ) -> ValueMappingContext -> ValueMappingContext
includeDataFrameInfo declInfos ctx =
    let
        newDataFrameInfo =
            declInfos
                |> List.map (\( _, ( varName, typeFullName ) ) -> ( typeFullName, varName ))
                |> Dict.fromList
    in
    { ctx | dataFrameColumnsObjects = Dict.union ctx.dataFrameColumnsObjects newDataFrameInfo }


checkForDataFrameColumndsDeclaration : MappingContextInfo () -> ( Name.Name, va, Type () ) -> Maybe ( Scala.MemberDecl, ( String, FQName.FQName ) )
checkForDataFrameColumndsDeclaration ctx ( name, _, tpe ) =
    let
        varNewName =
            (name |> Name.toCamelCase) ++ "Columns"
    in
    case tpe of
        Type.Reference _ _ [ (Type.Reference _ typeName _) as argType ] ->
            if isCandidateForDataFrame tpe ctx then
                Just ( generateLocalVariableForDataFrameColumns ctx ( varNewName, name, argType ), ( varNewName, typeName ) )

            else
                Nothing

        _ ->
            Nothing


generateLocalVariableForDataFrameColumns : MappingContextInfo () -> ( String, Name.Name, Type a ) -> Scala.MemberDecl
generateLocalVariableForDataFrameColumns ctx ( name, originalName, tpe ) =
    let
        nameInfo =
            isTypeReferenceToSimpleTypesRecord tpe ctx

        typeNameInfo =
            Maybe.map
                (\( typePath, simpleTypeName ) -> Just (Scala.TypeRef typePath (simpleTypeName |> Name.toTitleCase)))
                nameInfo

        objectReference =
            Maybe.map
                (\( typePath, simpleTypeName ) ->
                    Scala.New typePath ((simpleTypeName |> Name.toTitleCase) ++ "Wrapper") [ Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase originalName)) ]
                )
                nameInfo
    in
    Scala.ValueDecl
        { modifiers = []
        , pattern = Scala.NamedMatch name
        , valueType = Maybe.withDefault Nothing typeNameInfo
        , value = Maybe.withDefault Scala.Unit objectReference
        }


generateArgumentDeclarationForFunction : MappingContextInfo () -> FunctionClassification -> ( Name.Name, Type (), Type () ) -> List Scala.ArgDecl
generateArgumentDeclarationForFunction ctx currentFunctionClassification ( name, _, tpe ) =
    [ Scala.ArgDecl [] (mapTypeReference tpe currentFunctionClassification ctx) (name |> generateParameterName) Nothing ]


generateParameterName : Name.Name -> String
generateParameterName name =
    let
        scalaName =
            name |> Name.toCamelCase
    in
    if Set.member scalaName scalaKeywords || Set.member scalaName javaObjectMethods then
        "_" ++ scalaName

    else
        scalaName


processParameters : List ( Name.Name, Type (), Type () ) -> FunctionClassification -> MappingContextInfo () -> List (List Scala.ArgDecl)
processParameters inputTypes currentFunctionClassification ctx =
    inputTypes |> List.map (generateArgumentDeclarationForFunction ctx currentFunctionClassification)


mapFunctionBody : Value.Definition () (Type ()) -> ValueMappingContext -> ( Scala.Value, List GenerationIssue )
mapFunctionBody value ctx =
    let
        functionToMap =
            if ctx.currentFunctionClassification == FromComplexValuesToDataFrames || ctx.currentFunctionClassification == FromComplexToValues then
                FunctionMappingsForPlainScala.mapValueForPlainScala

            else
                mapValue
    in
    functionToMap value.body ctx
