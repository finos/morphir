module Morphir.Snowpark.AccessElementMapping exposing (
    mapConstructorAccess
    , mapFieldAccess
    , mapReferenceAccess
    , mapVariableAccess )

{-| This module contains functions to generate code like `a.b` or `a`.
|-}


import Morphir.IR.Name as Name
import Morphir.IR.Type as IrType
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.MappingContext as MappingContext
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Snowpark.MappingContext exposing (isUnionTypeWithoutParams
            , getReplacementForIdentifier)
import Html.Attributes exposing (name)
import Morphir.IR.FQName as FQName
import Morphir.IR.Value exposing (Value(..))
import Morphir.Snowpark.ReferenceUtils exposing (isValueReferenceToSimpleTypesRecord
           , scalaReferenceToUnionTypeCase
           , scalaPathToModule)
import Morphir.IR.Value as Value
import Morphir.Snowpark.MappingContext exposing (isAnonymousRecordWithSimpleTypes)
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)

mapFieldAccess : va -> (Value ta (IrType.Type ())) -> Name.Name -> ValueMappingContext -> Scala.Value
mapFieldAccess _ value name ctx =
   (let
       simpleFieldName = name |> Name.toCamelCase
       valueIsFunctionParameter = 
            case value of
                Value.Variable _ varName -> (varName, List.member varName ctx.parameters)
                _ -> (Name.fromString "a",False)
     in
     case (isValueReferenceToSimpleTypesRecord value ctx.typesContextInfo, valueIsFunctionParameter, value) of
       (_, (paramName, True), _) -> 
            Scala.Ref [paramName |> Name.toCamelCase] simpleFieldName
       (Just (path, refererName), (_, False), _) -> 
            Scala.Ref (path ++ [refererName |> Name.toTitleCase]) simpleFieldName
       _ ->
            (if isAnonymousRecordWithSimpleTypes (value |> Value.valueAttribute) ctx.typesContextInfo then
                applySnowparkFunc "col" [Scala.Literal (Scala.StringLit (Name.toCamelCase name)) ]
             else 
                Scala.Literal (Scala.StringLit "Field access to not converted")))

mapVariableAccess : (IrType.Type a) -> Name.Name -> ValueMappingContext -> Scala.Value
mapVariableAccess _ name ctx =
    case getReplacementForIdentifier name ctx of
        Just replacement ->
            replacement
        _ ->
            Scala.Variable (name |> Name.toCamelCase)

mapConstructorAccess : (IrType.Type a) -> FQName.FQName -> ValueMappingContext -> Scala.Value
mapConstructorAccess tpe name ctx =
    case (tpe, name) of
        ((IrType.Reference _ _ _),  ([ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ]))  ->
            applySnowparkFunc "lit" [Scala.Literal Scala.NullLit]
        (IrType.Reference _ typeName _, _) ->
            if isUnionTypeWithoutParams typeName ctx.typesContextInfo then
                scalaReferenceToUnionTypeCase typeName name
            else 
                Scala.Literal (Scala.StringLit "Constructor access not converted")
        _ -> 
            Scala.Literal (Scala.StringLit "Constructor access not converted")

mapReferenceAccess : (IrType.Type ()) -> FQName.FQName -> ValueMappingContext -> Scala.Value
mapReferenceAccess tpe name ctx =
   if MappingContext.isDataFrameFriendlyType tpe ctx.typesContextInfo then
        let
            nsName = scalaPathToModule name
            containerObjectFieldName = FQName.getLocalName name |> Name.toCamelCase
        in 
        Scala.Ref (nsName ) containerObjectFieldName
   else
        (Scala.Literal (Scala.StringLit "Reference access not converted"))