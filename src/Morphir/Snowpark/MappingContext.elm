module Morphir.Snowpark.MappingContext exposing 
      (processDistributionModules
      , isRecordWithSimpleTypes
      , isRecordWithComplexTypes
      , isTypeAlias
      , isUnionTypeWithoutParams
      , isUnionTypeWithParams
      , isUnionTypeRefWithoutParams
      , isBasicType
      , MappingContextInfo
      , emptyContext
      , isCandidateForDataFrame
      , ValueMappingContext
      , emptyValueMappingContext )

{-| This module contains functions to collect information about type definitions in a distribution.
It classifies type definitions in the following kinds:
   - records with 'simple' or basic types (canditate to be treated as a dataframe)
   - records containing other records
   - Union types or Custom types with name-only constructors
   - Union types or Custom types with complex constructors
   - Builtin type aliases
|-}

import Dict exposing (Dict)
import Morphir.IR.Type as Type exposing (Type, Type(..), Definition(..))
import Morphir.IR.Module as Module
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.FQName as FQName
import Morphir.IR.Package as Package
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name exposing (Name)

type TypeDefinitionClassification a =
   RecordWithSimpleTypes
   | RecordWithComplexTypes
   | UnionTypeWithoutParams
   | UnionTypeWithParams
   | TypeAlias (Type a)

type alias MappingContextInfo a = 
    Dict FQName (TypeClassificationState a)

type alias ValueMappingContext = 
   { parameters: List Name
   , typesContextInfo : MappingContextInfo ()
   }

emptyValueMappingContext : ValueMappingContext
emptyValueMappingContext = { parameters = []
                           , typesContextInfo = emptyContext }


emptyContext : MappingContextInfo a
emptyContext = Dict.empty

isRecordWithSimpleTypes : FQName -> MappingContextInfo a -> Bool
isRecordWithSimpleTypes name ctx = 
   case Dict.get name ctx of
       Just (TypeClassified RecordWithSimpleTypes) -> True
       _ -> False

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

isUnionTypeRefWithoutParams : Type a -> MappingContextInfo a -> Bool
isUnionTypeRefWithoutParams tpe ctx =
   case tpe of
       Type.Reference _ name _ -> isUnionTypeWithoutParams name ctx
       _ -> False


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
isCandidateForDataFrame typeRef ctx=
   case typeRef of
      Type.Reference _ 
                     ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) 
                     [ Type.Reference _  itemTypeName [] ] ->
         isRecordWithSimpleTypes itemTypeName ctx
      _ -> False


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

isAliasedBasicTypeWithPendingClassification : TypeClassificationState a -> Bool
isAliasedBasicTypeWithPendingClassification transitoryTypeClassification =
    case transitoryTypeClassification of
        TypeClassified (TypeAlias tpe) -> isBasicType tpe
        _ -> False


isUnionType : Type a -> MappingContextInfo a -> Bool
isUnionType tpe ctx =
  let 
     isUnionTypePred = (\t -> case t of
                              TypeClassified UnionTypeWithoutParams -> True
                              TypeClassified UnionTypeWithParams -> True
                              _ -> False)
                            
   in case tpe of
         Reference  _ name _ -> 
            Dict.get name ctx
            |> Maybe.map isUnionTypePred 
            |> Maybe.withDefault False
         _ -> False

isAliasOfBasicType : Type a -> MappingContextInfo a -> Bool
isAliasOfBasicType tpe ctx =
   case tpe of
      Reference  _ name _ -> 
           Dict.get name ctx
           |> Maybe.map isAliasedBasicTypeWithPendingClassification 
           |> Maybe.withDefault False
      _ -> False

classifyActualType : Type a -> MappingContextInfo a -> TypeClassificationState a
classifyActualType  tpe ctx = 
   case tpe of
       Record _ members ->
            if List.all (\t -> (isBasicType t.tpe) 
                               || (isUnionType t.tpe ctx) 
                               || (isAliasOfBasicType t.tpe ctx)) members then
               TypeClassified RecordWithSimpleTypes 
            else 
               TypeWithPendingClassification (Just tpe)
       Reference _ _  _ ->
            if isBasicType tpe then
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
