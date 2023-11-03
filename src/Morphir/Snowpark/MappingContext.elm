module Morphir.Snowpark.MappingContext exposing 
      (processDistributionModules
      , isRecordWithSimpleTypes
      , isRecordWithComplexTypes
      , isTypeAlias
      , isUnionTypeWithoutParams
      , isUnionTypeWithParams
      , isUnionTypeRefWithParams
      , isUnionTypeRefWithoutParams
      , isBasicType
      , MappingContextInfo
      , emptyContext
      , isCandidateForDataFrame
      , ValueMappingContext
      , emptyValueMappingContext
      , isAnonymousRecordWithSimpleTypes
      , getReplacementForIdentifier
      , isDataFrameFriendlyType
      , isLocalFunctionName
      , isTypeRefToRecordWithSimpleTypes
      , isAliasedBasicType
      , getLocalVariableIfDataFrameReference
      , getFieldsNamesIfRecordType
      , addReplacementforIdentifier
      , isListOfDataFrameFriendlyType )

{-| This module contains functions to collect information about type definitions in a distribution.
It classifies type definitions in the following kinds:
   - records with 'simple' or basic types (canditate to be treated as a dataframe)
   - records containing other records
   - Union types or Custom types with name-only constructors
   - Union types or Custom types with complex constructors
   - Builtin type aliases
|-}

import Dict exposing (Dict)
import Morphir.Scala.AST as Scala
import Morphir.IR.Type as Type exposing (Type, Type(..), Definition(..))
import Morphir.IR.Module as Module
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.FQName as FQName
import Morphir.IR.Package as Package
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Path as Path

type TypeDefinitionClassification a =
   RecordWithSimpleTypes (List Name)
   | RecordWithComplexTypes
   | UnionTypeWithoutParams 
   | UnionTypeWithParams
   | TypeAlias (Type a)

type alias MappingContextInfo a = 
    Dict FQName (TypeClassificationState a)

type alias ValueMappingContext = 
   { parameters: List Name
   , typesContextInfo : MappingContextInfo ()
   , inlinedIds: Dict Name Scala.Value
   , packagePath: Path.Path
   , dataFrameColumnsObjects: Dict FQName String
   }

emptyValueMappingContext : ValueMappingContext
emptyValueMappingContext = { parameters = []
                           , inlinedIds = Dict.empty
                           , typesContextInfo = emptyContext
                           , packagePath = Path.fromString "default" 
                           , dataFrameColumnsObjects = Dict.empty
                           }

getReplacementForIdentifier : Name -> ValueMappingContext -> Maybe Scala.Value
getReplacementForIdentifier name ctx =
   Dict.get name ctx.inlinedIds

addReplacementforIdentifier : Name -> Scala.Value -> ValueMappingContext -> ValueMappingContext
addReplacementforIdentifier name value ctx =
   let
      newReplacedIds = Dict.insert name value ctx.inlinedIds
   in
   { ctx | inlinedIds = newReplacedIds }

emptyContext : MappingContextInfo a
emptyContext = Dict.empty

isLocalFunctionName : FQName -> ValueMappingContext -> Bool
isLocalFunctionName name ctx =
   (FQName.getPackagePath name) == ctx.packagePath

isRecordWithSimpleTypes : FQName -> MappingContextInfo a -> Bool
isRecordWithSimpleTypes name ctx = 
   case Dict.get name ctx of
       Just (TypeClassified (RecordWithSimpleTypes _)) -> True
       _ -> False

isTypeRefToRecordWithSimpleTypes : Type a ->  MappingContextInfo a -> Bool
isTypeRefToRecordWithSimpleTypes tpe ctx =
   typeRefNamePredicate tpe isRecordWithSimpleTypes ctx

isRecordWithComplexTypes : FQName -> MappingContextInfo a -> Bool
isRecordWithComplexTypes name ctx = 
   case Dict.get name ctx of
       Just (TypeClassified RecordWithComplexTypes) -> True
       _ -> False

isUnionTypeWithoutParams : FQName -> MappingContextInfo a -> Bool
isUnionTypeWithoutParams name ctx = 
   case Dict.get name ctx of
       Just (TypeClassified UnionTypeWithoutParams) -> True
       _ -> False

typeRefNamePredicate : Type a -> (FQName -> MappingContextInfo a -> Bool) -> MappingContextInfo a -> Bool
typeRefNamePredicate tpe predicateToCheckOnName ctx =
   case tpe of
       Type.Reference _ name _ -> predicateToCheckOnName name ctx
       _ -> False

isUnionTypeRefWithoutParams : Type a -> MappingContextInfo a -> Bool
isUnionTypeRefWithoutParams tpe ctx =
   typeRefNamePredicate tpe isUnionTypeWithoutParams ctx

isUnionTypeRefWithParams : Type a -> MappingContextInfo a -> Bool
isUnionTypeRefWithParams tpe ctx =
   typeRefNamePredicate tpe isUnionTypeWithParams ctx

isUnionTypeWithParams : FQName -> MappingContextInfo a -> Bool
isUnionTypeWithParams name ctx = 
   case Dict.get name ctx of
       Just (TypeClassified UnionTypeWithParams) -> True
       _ -> False
isTypeAlias : FQName -> MappingContextInfo a -> Bool
isTypeAlias name ctx = 
   case Dict.get name ctx of
       Just (TypeClassified (TypeAlias _)) -> True
       _ -> False
     
isCandidateForDataFrame : (Type ()) -> MappingContextInfo () -> Bool
isCandidateForDataFrame typeRef ctx =
   case typeRef of
      Type.Reference _ 
                     ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) 
                     [ Type.Reference _  itemTypeName [] ] ->
         isRecordWithSimpleTypes itemTypeName ctx
      Type.Reference _ 
                     ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) 
                     [ Type.Record _ fields ] ->
         fields
            |> List.all (\{tpe} -> isDataFrameFriendlyType tpe ctx )
      _ -> False

isListOfDataFrameFriendlyType : (Type ()) -> MappingContextInfo () -> Bool
isListOfDataFrameFriendlyType typeRef ctx =
   case typeRef of
      Type.Reference _ 
                     ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) 
                     [ tpe ] ->
         isDataFrameFriendlyType tpe ctx
      _ ->
         False

getLocalVariableIfDataFrameReference : Type.Type () -> ValueMappingContext -> Maybe String
getLocalVariableIfDataFrameReference tpe ctx =
   case tpe of
       Type.Reference _ typeName _ ->
          Dict.get typeName ctx.dataFrameColumnsObjects
       _ ->
          Nothing

isAnonymousRecordWithSimpleTypes : Type.Type () -> MappingContextInfo () -> Bool
isAnonymousRecordWithSimpleTypes tpe ctx = 
   case tpe of
       Type.Record _ fields -> 
           List.all (\field -> isDataFrameFriendlyType field.tpe ctx) fields
       _ -> 
           False

type TypeClassificationState a = 
   TypeClassified (TypeDefinitionClassification a)
   | TypeWithPendingClassification (Maybe (Type a))
   | TypeNotClassified

classifyType : Type.Definition () -> MappingContextInfo () -> (TypeClassificationState ())
classifyType typeDefinition ctx =
   case typeDefinition of
       Type.TypeAliasDefinition _ t ->
         classifyActualType t ctx
       Type.CustomTypeDefinition _  {value} -> 
         let
             zeroArgConstructors =
                value 
                  |> Dict.values
                  |> List.all (\args -> 0 == (List.length args))
         in
         if zeroArgConstructors then
            TypeClassified UnionTypeWithoutParams
         else
            TypeClassified UnionTypeWithParams


isBasicType : Type a -> Bool
isBasicType tpe =
   case tpe of
       Reference _ ([["morphir"],["s","d","k"]],[["basics"]],_) _ -> True
       Reference _ ([["morphir"],["s","d","k"]],[["string"]],_) _ -> True
       _ -> False
       
-- TODO: we need to improve this mechanism and remove this function
isAliasedBasicType : Type a -> MappingContextInfo a -> Bool
isAliasedBasicType tpe ctx =
   case tpe of
       Type.Reference _ fqname [] -> 
         Maybe.withDefault False (Dict.get fqname ctx |> Maybe.map isAliasedBasicTypeWithPendingClassification)
       _ -> False

isAliasedBasicTypeWithPendingClassification : TypeClassificationState a -> Bool
isAliasedBasicTypeWithPendingClassification transitoryTypeClassification =
    transitoryTypeClassification
      |> aliasedBasicTypeWithPendingClassification 
      |> Maybe.map isBasicType
      |> Maybe.withDefault False
   --  case transitoryTypeClassification of
   --      TypeClassified (TypeAlias tpe) -> isBasicType tpe
   --      _ -> False

aliasedBasicTypeWithPendingClassification : TypeClassificationState a -> Maybe (Type a)
aliasedBasicTypeWithPendingClassification transitoryTypeClassification =
    case transitoryTypeClassification of
        TypeClassified (TypeAlias tpe) -> Just tpe
        _ -> Nothing

isUnionType : Type a -> MappingContextInfo a -> Bool
isUnionType tpe ctx =
  (let 
     isUnionTypePred = (\t -> case t of
                              TypeClassified UnionTypeWithoutParams -> True
                              TypeClassified UnionTypeWithParams -> True
                              _ -> False)
                            
   in case tpe of
         Reference  _ name _ -> 
            Dict.get name ctx
            |> Maybe.map isUnionTypePred 
            |> Maybe.withDefault False
         _ -> False)

isAliasOfBasicType : Type a -> MappingContextInfo a -> Bool
isAliasOfBasicType tpe ctx =
   case tpe of
      Reference  _ name _ -> 
           Dict.get name ctx
           |> Maybe.map isAliasedBasicTypeWithPendingClassification 
           |> Maybe.withDefault False
      _ -> False

isAliasOfDataFrameFriendlyType : Type a -> MappingContextInfo a -> Bool
isAliasOfDataFrameFriendlyType tpe ctx =
   case tpe of
      Reference  _ name _ -> 
           (Dict.get name ctx
           |> Maybe.map aliasedBasicTypeWithPendingClassification
           |> Maybe.withDefault Nothing
           |> Maybe.map (\x -> isDataFrameFriendlyType x ctx)
           |> Maybe.withDefault False)
      _ -> False

isMaybeOfDataFrameFriendlyType : Type a -> MappingContextInfo a -> Bool
isMaybeOfDataFrameFriendlyType tpe ctx =
   case tpe of
      Type.Reference _ ([["morphir"],["s","d","k"]],[["maybe"]],["maybe"]) [typeArg] ->
         isDataFrameFriendlyType typeArg ctx
      _ -> 
         False

isDataFrameFriendlyType : Type a -> MappingContextInfo a -> Bool
isDataFrameFriendlyType tpe ctx =
      isBasicType tpe
      || (isUnionType tpe ctx)
      || (isAliasOfDataFrameFriendlyType tpe ctx)
      || (isMaybeOfDataFrameFriendlyType tpe ctx)


getFieldsNamesIfRecordType : Type a -> MappingContextInfo a -> Maybe (List Name)
getFieldsNamesIfRecordType tpe ctx =
   case tpe of
      Reference _ typeName _ ->
         case Dict.get typeName ctx of
             Just (TypeClassified (RecordWithSimpleTypes fieldNames)) -> 
               Just fieldNames
             _ ->
               Nothing
      _ -> 
         Nothing


classifyActualType : Type a -> MappingContextInfo a -> TypeClassificationState a
classifyActualType  tpe ctx = 
   case tpe of
       Record _ members ->
            if List.all (\t -> isDataFrameFriendlyType t.tpe ctx) members then
               TypeClassified (RecordWithSimpleTypes (members |> List.map .name))
            else 
               TypeWithPendingClassification (Just tpe)
       Reference _ _  _ ->
            if isBasicType tpe || isUnionType tpe ctx then
               TypeClassified (TypeAlias tpe)
            else
               TypeWithPendingClassification (Just tpe)
       _ -> TypeNotClassified

simpleName packagePath modName name = 
  FQName.fQName packagePath modName name

processModuleDefinition : Package.PackageName -> ModuleName -> MappingContextInfo () -> AccessControlled (Module.Definition () (Type ())) -> MappingContextInfo ()
processModuleDefinition packagePath modulePath currentResult moduleDefinition =
    moduleDefinition.value.types
    |> Dict.toList
    |> List.map (\(name, acc) -> (name, acc.value.value))
    |> List.map (\(name, typeDefinition) -> ((simpleName packagePath modulePath name), (classifyType  typeDefinition currentResult)))
    |> Dict.fromList
    |> Dict.union currentResult


processSecondPassOnType : FQName -> TypeClassificationState () -> MappingContextInfo () -> MappingContextInfo ()
processSecondPassOnType name typeClassification ctx =
   case typeClassification of
       TypeClassified _ -> ctx
       TypeWithPendingClassification (Just tpe) -> 
           case classifyActualType tpe ctx of
               TypeClassified newType -> 
                     Dict.update name (\_ -> Just (TypeClassified newType)) ctx
               -- If we could not classify a record after the second pass classify it as 'complex'
               TypeWithPendingClassification (Just (Record  _ _)) -> 
                     Dict.update name (\_ -> Just (TypeClassified RecordWithComplexTypes)) ctx
               _ -> ctx
       _ -> ctx

processDistributionModules : Package.PackageName -> Package.Definition () (Type ()) -> MappingContextInfo ()
processDistributionModules packagePath package =
   let 
      firstPass = package.modules 
                  |> Dict.toList
                  |> (List.foldr 
                        (\(modName, modDef) curretnResult -> processModuleDefinition packagePath modName curretnResult modDef)
                        Dict.empty)
      secondPass = firstPass
                   |> Dict.foldr (\key value result -> processSecondPassOnType key value result) firstPass
      in secondPass
