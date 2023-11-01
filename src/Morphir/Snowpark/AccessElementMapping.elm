module Morphir.Snowpark.AccessElementMapping exposing (
    mapConstructorAccess
    , mapFieldAccess
    , mapReferenceAccess
    , mapVariableAccess )

{-| This module contains functions to generate code like `a.b` or `a`.
|-}

import Dict exposing (Dict)
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
import Morphir.Snowpark.MappingContext exposing (isUnionTypeWithParams)
import Morphir.IR.Value as Value
import String exposing (replace)


checkForDataFrameVariableReference : Value ta (IrType.Type ()) -> ValueMappingContext -> Maybe String
checkForDataFrameVariableReference value ctx =
    case Value.valueAttribute value of
        IrType.Reference _ typeName _ -> 
            Dict.get typeName ctx.dataFrameColumnsObjects
        _ -> 
            Nothing

mapFieldAccess : va -> (Value ta (IrType.Type ())) -> Name.Name -> ValueMappingContext -> Scala.Value
mapFieldAccess _ value name ctx =
   (let
       simpleFieldName = name |> Name.toCamelCase
       valueIsFunctionParameter =
            case value of
                Value.Variable _ varName -> 
                    if List.member varName ctx.parameters then
                        Just <| Name.toCamelCase varName
                    else
                        Nothing
                _ -> 
                    Nothing
       valueIsDataFrameColumnAccess = 
            case (value, checkForDataFrameVariableReference value ctx) of
                (Value.Variable  _ _, Just replacement) -> 
                    Just replacement
                _ -> 
                    Nothing
     in
     case (isValueReferenceToSimpleTypesRecord value ctx.typesContextInfo, valueIsFunctionParameter, valueIsDataFrameColumnAccess) of
       (_,Just replacement, _ ) -> 
            Scala.Ref [replacement] simpleFieldName
       (_,_, Just replacement) -> 
            Scala.Ref [replacement] simpleFieldName
       (Just (path, refererName), Nothing, Nothing) -> 
            Scala.Ref (path ++ [refererName |> Name.toTitleCase]) simpleFieldName
       _ ->
            (if isAnonymousRecordWithSimpleTypes (value |> Value.valueAttribute) ctx.typesContextInfo then
                applySnowparkFunc "col" [Scala.Literal (Scala.StringLit (Name.toCamelCase name)) ]
             else 
                Scala.Literal (Scala.StringLit "Field access to not converted")))

mapVariableAccess : Name.Name ->  (Value ta (IrType.Type ()))  -> ValueMappingContext -> Scala.Value
mapVariableAccess name nameAccess ctx =
    case (getReplacementForIdentifier name ctx, checkForDataFrameVariableReference nameAccess ctx) of
        (Just replacement, _) ->
            replacement
        (_, Just replacementStr) ->
            Scala.Variable replacementStr
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
            else if isUnionTypeWithParams typeName ctx.typesContextInfo then
                applySnowparkFunc "object_construct" [
                        applySnowparkFunc "lit" [Scala.Literal <| Scala.StringLit "__tag"], 
                        applySnowparkFunc "lit" [Scala.Literal <| Scala.StringLit (name |> FQName.getLocalName |> Name.toTitleCase)] ]
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