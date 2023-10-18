module Morphir.Snowpark.AccessElementMapping exposing (
    mapConstructorAccess
    , mapFieldAccess
    , mapReferenceAccess
    , mapVariableAccess )

{-| This module contains functions to generate code like `a.b` or `a`.
|-}

import List
import Morphir.IR.Name as Name
import Morphir.IR.Type as IrType
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.MappingContext as MappingContext
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.Snowpark.MappingContext exposing (MappingContextInfo, isRecordWithSimpleTypes)
import Morphir.Snowpark.MappingContext exposing (isUnionTypeWithoutParams)
import Html.Attributes exposing (name)
import Morphir.IR.FQName as FQName
import Morphir.IR.Value exposing (Value(..))

isReferenceToSimpleTypesRecord : (Value ta (IrType.Type a)) -> MappingContextInfo a -> Maybe (Scala.Path, Name.Name)
isReferenceToSimpleTypesRecord expression ctx =
   case expression of
       Variable (IrType.Reference _ typeName _) _ -> 
            if isRecordWithSimpleTypes typeName ctx then
                Just (scalaPathToModule typeName, (FQName.getLocalName typeName))
            else
                Nothing
       _ -> 
            Nothing

mapFieldAccess : va -> (Value ta (IrType.Type a)) -> Name.Name -> MappingContextInfo a -> Scala.Value
mapFieldAccess _ value name ctx =
   let
       simpleFieldName = name |> Name.toCamelCase
   in
   case isReferenceToSimpleTypesRecord value ctx of
       Just (path, refererName) -> Scala.Ref (path ++ [refererName |> Name.toTitleCase]) simpleFieldName
       _ -> Scala.Literal (Scala.StringLit "Field access not converted")


mapVariableAccess : (IrType.Type a) -> Name.Name -> MappingContextInfo a -> Scala.Value
mapVariableAccess _ name _ =
   Scala.Variable (name |> Name.toCamelCase)   

mapConstructorAccess : (IrType.Type a) -> FQName.FQName -> MappingContextInfo a -> Scala.Value
mapConstructorAccess tpe name ctx =
    case tpe of
        IrType.Reference _ typeName _ ->
            if isUnionTypeWithoutParams typeName ctx then
                let
                    nsName = scalaPathToModule name
                    containerObjectName = FQName.getLocalName typeName |> Name.toTitleCase
                    containerObjectFieldName = FQName.getLocalName name |> Name.toTitleCase
                in 
                Scala.Ref (nsName ++ [containerObjectName]) containerObjectFieldName
            else 
                (Scala.Literal (Scala.StringLit "Field access not converted"))
        _ -> (Scala.Literal (Scala.StringLit "Field access not converted"))

scalaPathToModule : FQName.FQName -> Scala.Path
scalaPathToModule name =
    let
        packagePath =  FQName.getPackagePath name |> List.map Name.toCamelCase
        modulePath = case FQName.getModulePath name |> List.reverse of
                        (last::restInverted) -> ((Name.toTitleCase last) :: (List.map Name.toCamelCase restInverted)) |> List.reverse
                        _ -> []
    in
        packagePath ++ modulePath

mapReferenceAccess : (IrType.Type a) -> FQName.FQName -> Scala.Value
mapReferenceAccess tpe name =
   if MappingContext.isBasicType tpe then
        let
            nsName = scalaPathToModule name
            containerObjectFieldName = FQName.getLocalName name |> Name.toCamelCase
        in 
        Scala.Ref (nsName ) containerObjectFieldName
   else
        (Scala.Literal (Scala.StringLit "Reference access not converted"))