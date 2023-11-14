module Morphir.Snowpark.Backend exposing (..)

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
import Morphir.Scala.AST as Scala
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName
import Morphir.Scala.Common exposing (scalaKeywords, mapValueName, javaObjectMethods)
import Morphir.Snowpark.Constants as Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.AccessElementMapping exposing (
    mapFieldAccess
    , mapReferenceAccess
    , mapVariableAccess
    , mapConstructorAccess)
import Morphir.Snowpark.RecordWrapperGenerator as RecordWrapperGenerator
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord, mapLiteral)
import Morphir.Snowpark.TypeRefMapping exposing (mapTypeReference, mapFunctionReturnType)
import Morphir.Snowpark.MapFunctionsMapping as MapFunctionsMapping
import Morphir.Snowpark.PatternMatchMapping exposing (mapPatternMatch)
import Morphir.Snowpark.MappingContext as MappingContext exposing (
            MappingContextInfo
            , GlobalDefinitionInformation
            , emptyValueMappingContext
            , getFunctionClassification
            , typeRefIsListOf
            , ValueMappingContext
            , FunctionClassification
            , isCandidateForDataFrame
            , isFunctionClassificationReturningDataFrameExpressions
            , isFunctionReturningDataFrameExpressions
            , isTypeRefToRecordWithSimpleTypes
            , isTypeRefToRecordWithComplexTypes )
import Morphir.Snowpark.MappingContext exposing (isRecordWithComplexTypes)
import Morphir.Snowpark.ReferenceUtils exposing (scalaPathToModule)
import Morphir.Snowpark.Utils exposing (collectMaybeList)
import Morphir.Snowpark.MappingContext exposing (isRecordWithSimpleTypes)
import Morphir.Snowpark.MappingContext exposing (isAnonymousRecordWithSimpleTypes)

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
           Maybe.Just (mapValue value.body ctx)

mapValue : Value ta (Type ()) -> ValueMappingContext -> Scala.Value
mapValue value ctx =
    case value of
        Literal tpe literal ->
            mapLiteral tpe literal
        Field tpe val name ->
            mapFieldAccess tpe val name ctx mapValue
        Variable _ name as varAccess ->
            mapVariableAccess name varAccess ctx
        Constructor tpe name ->
            mapConstructorAccess tpe name ctx
        List listType values ->
            mapListCreation listType values ctx
        Reference tpe name ->
            mapReferenceAccess tpe name ctx
        Apply _ _ _ ->
            MapFunctionsMapping.mapFunctionsMapping value mapValue ctx
        PatternMatch tpe expr cases ->
            mapPatternMatch (tpe, expr, cases) mapValue ctx
        IfThenElse _ condition thenExpr elseExpr ->
            mapIfThenElse condition thenExpr elseExpr ctx
        LetDefinition _ name definition body ->
            mapLetDefinition name definition body ctx
        FieldFunction _ [name] ->
            Constants.applySnowparkFunc "col" [(Scala.Literal (Scala.StringLit name))]
        Value.Tuple _ tupleElements ->
            Constants.applySnowparkFunc "array_construct" <| List.map (\e -> mapValue e ctx) tupleElements
        Value.Record tpe fields ->
            mapRecordCreation tpe fields ctx
        _ ->
            Scala.Literal (Scala.StringLit ("Unsupported element"))


mapRecordCreation : Type () -> Dict.Dict (Name.Name) (Value ta (Type ())) -> ValueMappingContext -> Scala.Value
mapRecordCreation tpe fields ctx =
    if isTypeRefToRecordWithComplexTypes tpe ctx.typesContextInfo then
        mapRecordCreationToCaseClassCreation tpe fields ctx
    else 
        if (isTypeRefToRecordWithSimpleTypes tpe ctx.typesContextInfo || 
            isAnonymousRecordWithSimpleTypes tpe ctx.typesContextInfo) && 
            isFunctionClassificationReturningDataFrameExpressions ctx.currentFunctionClassification  then
            MappingContext.getFieldInfoIfRecordType tpe ctx.typesContextInfo 
                |> Maybe.map (\fieldInfo -> collectMaybeList 
                                                            ((\(fieldName, _) -> 
                                                                (Dict.get fieldName fields) 
                                                                    |> Maybe.map (\argExpr -> mapValue argExpr ctx)))
                                                            fieldInfo  )
                |> Maybe.withDefault Nothing
                |> Maybe.map (applySnowparkFunc "array_construct")
                |> Maybe.withDefault (Scala.Literal (Scala.StringLit ("Record creation not converted1")))
        else
            Scala.Literal (Scala.StringLit ("Record creation not converted2"))


mapRecordCreationToCaseClassCreation : Type () -> Dict.Dict (Name.Name) (Value ta (Type ())) -> ValueMappingContext -> Scala.Value
mapRecordCreationToCaseClassCreation tpe fields ctx =
    case tpe of
        Type.Reference _ fullName [] ->
            let
                caseClassReference = 
                    Scala.Ref (scalaPathToModule fullName) (fullName |> FQName.getLocalName |> Name.toTitleCase)
                processArgs :  List (Name.Name, Type ()) -> Maybe (List Scala.ArgValue)
                processArgs fieldsInfo =
                    fieldsInfo
                        |> collectMaybeList (\(fieldName, _) -> 
                                                   Dict.get fieldName fields 
                                                    |> Maybe.map (\argExpr -> Scala.ArgValue (Just (Name.toCamelCase fieldName)) (mapValue argExpr ctx)))
            in
            MappingContext.getFieldInfoIfRecordType tpe ctx.typesContextInfo            
                |> Maybe.map processArgs
                |> Maybe.withDefault Nothing
                |> Maybe.map (\ctorArgs -> Scala.Apply caseClassReference ctorArgs)
                |> Maybe.withDefault (Scala.Literal (Scala.StringLit ("Record creation not converted!")))
        _ ->
            Scala.Literal (Scala.StringLit ("Record creation not converted"))


mapListCreation : (Type ()) -> List (Value ta (Type ())) -> ValueMappingContext -> Scala.Value
mapListCreation tpe values ctx =
    if typeRefIsListOf tpe (\innerTpe -> isTypeRefToRecordWithSimpleTypes innerTpe ctx.typesContextInfo) &&
        isFunctionClassificationReturningDataFrameExpressions ctx.currentFunctionClassification then
        applySnowparkFunc "array_construct"
            (values |> List.map (\v -> mapValue v ctx))
    else
        Scala.Apply 
            (Scala.Variable "Seq")
            (values |> List.map (\v -> Scala.ArgValue Nothing (mapValue v ctx)))


mapLetDefinition : Name.Name -> Value.Definition ta (Type ()) -> Value ta (Type ()) -> ValueMappingContext -> Scala.Value
mapLetDefinition name definition body ctx =
    case definition.inputTypes of
        [] -> 
            let 
                (pairs, bodyToConvert) = collectNestedLetDeclarations body []
                decls = ((name, definition) :: pairs)
                            |> List.map (\(pName, pDefinition) ->
                                            Scala.ValueDecl  { modifiers = []
                                                            , pattern = Scala.NamedMatch (pName |> Name.toCamelCase)
                                                            , valueType = Nothing
                                                            , value = mapValue pDefinition.body ctx
                                                            })
            in
            Scala.Block decls (mapValue bodyToConvert ctx)
        _ -> 
            Scala.Literal (Scala.StringLit ("Unsupported function let expression"))

collectNestedLetDeclarations : Value ta (Type ()) -> 
                                  List (Name.Name, Value.Definition ta (Type ())) ->
                                  (List (Name.Name, Value.Definition ta (Type ())), Value ta (Type ())) 
collectNestedLetDeclarations currentBody collectedPairs =
    case currentBody of
        Value.LetDefinition _ name definition body ->
            collectNestedLetDeclarations body ((name, definition)::collectedPairs)
        _ -> 
            (List.reverse collectedPairs, currentBody)


mapIfThenElse : Value ta (Type ()) -> Value ta (Type ()) -> Value ta (Type ()) -> ValueMappingContext -> Scala.Value
mapIfThenElse condition thenExpr elseExpr ctx =
   let
       whenCall = 
            Constants.applySnowparkFunc "when" [ mapValue condition ctx,  mapValue thenExpr ctx ]
   in
   Scala.Apply (Scala.Select whenCall "otherwise") [Scala.ArgValue Nothing (mapValue elseExpr ctx)]
