module Morphir.Snowpark.RecordWrapperGenerator exposing (generateRecordWrappers)

import Dict exposing (Dict)
import Morphir.Scala.AST as Scala
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Name exposing (Name, toTitleCase)
import Morphir.IR.Type as Type 
import Morphir.IR.Package as Package
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.MappingContext exposing (MappingContextInfo, isRecordWithSimpleTypes)
import Morphir.IR.Type exposing (Field)
import Morphir.IR.Name as Name
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.Constants exposing (typeRefForSnowparkType)
import Morphir.Snowpark.MappingContext exposing (isUnionTypeWithoutParams)


{-| This module contains to create wrappers for record declarations that represent tables.

For each record a Trait and an Object is generated with `Column` fields for each member.

For union types without parameters we are going to generate an object definition with accessors for each option.
|-}

generateRecordWrappers : Package.PackageName -> ModuleName -> MappingContextInfo () -> Dict Name (AccessControlled (Documented (Type.Definition ta))) -> List (Scala.Documented (Scala.Annotated Scala.TypeDecl))
generateRecordWrappers packageName moduleName ctx typesInModule = 
    typesInModule
       |> Dict.toList
       |> List.concatMap (processTypeDeclaration packageName moduleName ctx)
       

processTypeDeclaration : Package.PackageName -> ModuleName -> MappingContextInfo () -> (Name, (AccessControlled (Documented (Type.Definition ta)))) -> List (Scala.Documented (Scala.Annotated Scala.TypeDecl))
processTypeDeclaration packageName moduleName ctx (name, typeDeclAc) =
    -- For the moment we are going generating wrappers for record types
    case typeDeclAc.value.value of
        Type.TypeAliasDefinition _ (Type.Record _ members) -> 
            processRecordDeclaration 
                     name 
                     typeDeclAc.value.doc
                     members
                     (isRecordWithSimpleTypes (FQName.fQName packageName moduleName name) ctx)
        Type.CustomTypeDefinition _ constructorsAccess ->
            processUnionTypeDeclaration 
                     name 
                     constructorsAccess.value
                     (isUnionTypeWithoutParams (FQName.fQName packageName moduleName name) ctx)
        _ -> []


processUnionTypeDeclaration : Name -> Morphir.IR.Type.Constructors ta -> Bool -> List (Scala.Documented (Scala.Annotated Scala.TypeDecl))
processUnionTypeDeclaration name constructors noParams =
    if noParams then
        [ 
            objectForUnionWithNoParamsValues name constructors
        ]
    else 
        []


processRecordDeclaration : Name -> String -> (List (Field a)) ->  Bool -> List (Scala.Documented (Scala.Annotated Scala.TypeDecl))
processRecordDeclaration name doc fields recordWithSimpleTypes =
   if recordWithSimpleTypes then
    [
        traitForRecordWrapper name doc fields,
        objectForRecordWrapper name fields
    ] 
   else
    []

traitForRecordWrapper : Name -> String -> (List (Field a)) -> (Scala.Documented (Scala.Annotated Scala.TypeDecl))
traitForRecordWrapper name doc fields = 
  let 
     members = fields |> List.map generateTraitMember
  in 
  ( Scala.Documented (Just doc)
        (Scala.Annotated []
            (Scala.Trait
                { modifiers = 
                    []
                , name =
                    name |> toTitleCase
                , typeArgs =
                    []
                , members = 
                    members
                , extends =
                    []
                }
            )
        )) 

generateTraitMember : (Field a) -> (Scala.Annotated Scala.MemberDecl)
generateTraitMember field =
  (Scala.Annotated
            []
            (Scala.FunctionDecl
                {
                modifiers = []
                , name = (field.name |> Name.toCamelCase)
                , typeArgs = []
                , args = []
                , returnType = Just (typeRefForSnowparkType "Column") 
                , body = Nothing
                }))


objectForRecordWrapper : Name -> (List (Field a)) -> (Scala.Documented (Scala.Annotated Scala.TypeDecl))
objectForRecordWrapper name  fields = 
  let 
     nameToUse = name |> toTitleCase
     members = fields |> List.map generateObjectMember
  in 
  ( Scala.Documented Nothing
        (Scala.Annotated []
            (Scala.Object
                { modifiers = 
                    []
                , name =
                    nameToUse
                , members = 
                    members
                , extends =
                    [ Scala.TypeRef [] nameToUse ]
                , body = 
                    Nothing
                }
            )
        )) 

generateObjectMember : (Field a) -> (Scala.Annotated Scala.MemberDecl)
generateObjectMember field =
  (Scala.Annotated
            []
            (Scala.FunctionDecl
            {
             modifiers = []
            , name = (field.name |> Name.toCamelCase)
            , typeArgs = []
            , args = []
            , returnType = Just (typeRefForSnowparkType "Column") 
            , body = Just (applySnowparkFunc "col" [(Scala.Literal (Scala.StringLit (field.name |> Name.toCamelCase)))])
            }))



generateUnionTypeNameMember : String -> (Scala.Annotated Scala.MemberDecl)
generateUnionTypeNameMember optionName =
  (Scala.Annotated
            []
            (Scala.FunctionDecl
            {
             modifiers = []
            , name = optionName
            , typeArgs = []
            , args = []
            , returnType = Just (typeRefForSnowparkType "Column") 
            , body = Just (applySnowparkFunc "lit" [(Scala.Literal (Scala.StringLit optionName))])
            }))


objectForUnionWithNoParamsValues : Name -> Morphir.IR.Type.Constructors ta -> (Scala.Documented (Scala.Annotated Scala.TypeDecl))
objectForUnionWithNoParamsValues name constructors = 
  let 
     nameToUse = name |> toTitleCase
     members = constructors 
               |> Dict.toList
               |> List.map (\(constructorName, _) -> generateUnionTypeNameMember (Name.toTitleCase constructorName))
  in 
  ( Scala.Documented 
        Nothing
        (Scala.Annotated []
            (Scala.Object
                { modifiers = 
                    []
                , name =
                    nameToUse
                , members = 
                    members
                , extends =
                    []
                , body = 
                    Nothing
                }
            )
        )) 

        