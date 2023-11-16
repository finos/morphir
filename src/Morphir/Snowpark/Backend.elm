module Morphir.Snowpark.Backend exposing (mapDistribution, Options, mapFunctionDefinition)

import Dict
import List
import Set as Set
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (..)
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Module as Module 
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName
import Morphir.Scala.AST as Scala
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.Scala.Common exposing (scalaKeywords, mapValueName, javaObjectMethods)
import Morphir.Snowpark.RecordWrapperGenerator as RecordWrapperGenerator
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord, isTypeReferenceToSimpleTypesRecord)
import Morphir.Snowpark.TypeRefMapping exposing (mapTypeReference, mapFunctionReturnType)
import Morphir.Snowpark.MappingContext as MappingContext exposing (
            MappingContextInfo
            , GlobalDefinitionInformation
            , emptyValueMappingContext
            , getFunctionClassification
            , ValueMappingContext
            , FunctionClassification
            , isCandidateForDataFrame )
import Morphir.Snowpark.MappingContext exposing (FunctionClassification(..))
import Morphir.Snowpark.FunctionMappingsForPlainScala as FunctionMappingsForPlainScala
import Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)

type alias Options =
    {}

mapDistribution : Options -> Distribution -> FileMap
mapDistribution _ distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition distro packageName packageDef

mapPackageDefinition : Distribution -> Package.PackageName -> Package.Definition () (Type ()) -> FileMap
mapPackageDefinition _ packagePath packageDef =
    let
        contextInfo = MappingContext.processDistributionModules packagePath packageDef
        generatedScala =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( modulePath, moduleImpl ) ->
                        mapModuleDefinition packagePath modulePath moduleImpl contextInfo
                    )
    in
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


mapModuleDefinition : Package.PackageName -> Path -> AccessControlled (Module.Definition () (Type ())) -> GlobalDefinitionInformation () -> List Scala.CompilationUnit
mapModuleDefinition currentPackagePath currentModulePath accessControlledModuleDef ctxInfo =
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
                    ( parts |> (List.map Name.toCamelCase), lastName )

        moduleTypeDefinitions : List (Scala.Annotated Scala.MemberDecl)
        moduleTypeDefinitions = 
            accessControlledModuleDef.value.types
                |> RecordWrapperGenerator.generateRecordWrappers currentPackagePath currentModulePath ctxInfo
                |> List.map (\doc -> { annotations = doc.value.annotations, value = Scala.MemberTypeDecl (doc.value.value) } )

        functionMembers : List (Scala.Annotated Scala.MemberDecl)
        functionMembers =
            accessControlledModuleDef.value.values
                |> Dict.toList
                |> List.concatMap
                    (\( valueName, accessControlledValueDef ) ->
                        [ mapFunctionDefinition valueName accessControlledValueDef currentPackagePath currentModulePath ctxInfo
                        ]
                    )
                |> List.map Scala.withoutAnnotation
        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls = [( Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Scala.Annotated []
                        (Scala.Object
                            { modifiers =
                                case accessControlledModuleDef.access of
                                    Public ->
                                        []

                                    Private ->
                                        []
                            , name =
                                moduleName |> Name.toTitleCase
                            , members = 
                                (moduleTypeDefinitions ++ functionMembers)
                            , extends =
                                []
                            , body = Nothing
                            }
                        )
                    )
                )]
            }
    in
    [ moduleUnit ]


mapFunctionDefinition : Name.Name -> AccessControlled (Documented (Value.Definition () (Type ()))) ->  Path -> Path ->  GlobalDefinitionInformation () -> Scala.MemberDecl
mapFunctionDefinition functionName body currentPackagePath modulePath (typeContextInfo, functionsInfo) =
    let
       fullFunctionName = FQName.fQName currentPackagePath modulePath functionName
       functionClassification =  getFunctionClassification fullFunctionName functionsInfo
       parameters = processParameters body.value.value.inputTypes functionClassification typeContextInfo
       parameterNames = body.value.value.inputTypes |> List.map (\(name, _, _) -> name)
       valueMappingContext = { emptyValueMappingContext | typesContextInfo = typeContextInfo
                                                        , parameters = parameterNames
                                                        , functionClassificationInfo = functionsInfo
                                                        , currentFunctionClassification = functionClassification
                                                        , packagePath = currentPackagePath} 
       localDeclarations = 
            body.value.value.inputTypes                
                |> List.filterMap (checkForDataFrameColumndsDeclaration typeContextInfo)
       bodyCandidate = mapFunctionBody body.value.value (includeDataFrameInfo localDeclarations valueMappingContext)
       returnTypeToGenerate = mapFunctionReturnType body.value.value.outputType functionClassification typeContextInfo
    in
    Scala.FunctionDecl
            { modifiers = []
            , name = mapValueName functionName
            , typeArgs = []                                
            , args = parameters
            , returnType = 
                Just returnTypeToGenerate
            , body =
                case (localDeclarations |> List.map Tuple.first, bodyCandidate) of
                    ([], Just _) -> bodyCandidate
                    (declarations, Just bodyToUse) -> Just (Scala.Block declarations bodyToUse)
                    (_, _) -> Nothing
            }

includeDataFrameInfo : List (Scala.MemberDecl, (String, FQName.FQName)) -> ValueMappingContext -> ValueMappingContext
includeDataFrameInfo declInfos ctx =
    let
        newDataFrameInfo = declInfos 
                            |> List.map (\(_, (varName, typeFullName) ) -> (typeFullName, varName))
                            |> Dict.fromList
    in
    { ctx | dataFrameColumnsObjects = Dict.union ctx.dataFrameColumnsObjects newDataFrameInfo }

checkForDataFrameColumndsDeclaration :  MappingContextInfo () -> ( Name.Name, va, Type () ) -> Maybe (Scala.MemberDecl, (String, FQName.FQName))
checkForDataFrameColumndsDeclaration ctx (name, _,  tpe) =
    let
        varNewName = ((name |> Name.toCamelCase) ++ "Columns")
    in
    case tpe of
        Type.Reference _ _ [(Type.Reference _ typeName _) as argType] -> 
            if isCandidateForDataFrame tpe ctx then
                Just  (generateLocalVariableForDataFrameColumns ctx (varNewName, name, argType), (varNewName, typeName))
            else
                Nothing
        _ -> 
            Nothing

generateLocalVariableForDataFrameColumns : MappingContextInfo () -> ( String, Name.Name, Type a ) -> Scala.MemberDecl
generateLocalVariableForDataFrameColumns ctx (name, originalName, tpe) =
   let
      nameInfo =  
        isTypeReferenceToSimpleTypesRecord tpe ctx
      typeNameInfo = Maybe.map 
                           (\(typePath, simpleTypeName) -> Just (Scala.TypeRef typePath (simpleTypeName |> Name.toTitleCase) ))
                           nameInfo
      objectReference = Maybe.map 
                           (\(typePath, simpleTypeName) -> 
                                Scala.New typePath ((simpleTypeName |> Name.toTitleCase) ++ "Wrapper") [Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase originalName ))] )
                           nameInfo
   in
   Scala.ValueDecl {
    modifiers = []
    , pattern = (Scala.NamedMatch name)
    , valueType = Maybe.withDefault Nothing typeNameInfo
    , value = Maybe.withDefault Scala.Unit objectReference
    }

generateArgumentDeclarationForFunction : MappingContextInfo () -> FunctionClassification -> ( Name.Name, Type (), Type () ) -> List Scala.ArgDecl
generateArgumentDeclarationForFunction ctx currentFunctionClassification (name, _, tpe) =
    [Scala.ArgDecl [] (mapTypeReference tpe currentFunctionClassification ctx) (name |> generateParameterName) Nothing]

generateParameterName : Name.Name -> String
generateParameterName name =
    let
       scalaName = name |> Name.toCamelCase
    in
    if Set.member scalaName scalaKeywords || Set.member scalaName javaObjectMethods then
        "_" ++ scalaName
    else
        scalaName


processParameters : List ( Name.Name, Type (), Type () ) -> FunctionClassification -> MappingContextInfo () -> List (List Scala.ArgDecl)
processParameters inputTypes currentFunctionClassification ctx =
    inputTypes |> List.map (generateArgumentDeclarationForFunction ctx currentFunctionClassification)


mapFunctionBody : Value.Definition ta (Type ()) -> ValueMappingContext -> Maybe Scala.Value
mapFunctionBody value ctx =
    let
        functionToMap =
            if ctx.currentFunctionClassification == FromComplexValuesToDataFrames || ctx.currentFunctionClassification == FromComplexToValues then
                FunctionMappingsForPlainScala.mapValueForPlainScala
            else 
                mapValue
    in
    Maybe.Just (functionToMap value.body ctx)

