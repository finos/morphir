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
import Morphir.Snowpark.MappingContext exposing (isUnionTypeWithoutParams)
import Html.Attributes exposing (name)
import Morphir.IR.FQName as FQName
import Morphir.IR.Value exposing (Value(..))
import Morphir.Snowpark.ReferenceUtils exposing (isValueReferenceToSimpleTypesRecord
           , scalaReferenceToUnionTypeCase
           , scalaPathToModule)
import Morphir.IR.Value as Value

mapFieldAccess : va -> (Value ta (IrType.Type a)) -> Name.Name -> ValueMappingContext -> Scala.Value
mapFieldAccess _ value name ctx =
   let
       simpleFieldName = name |> Name.toCamelCase
       valueIsFunctionParameter = 
            case value of
                Value.Variable _ varName -> (varName, List.member varName ctx.parameters)
                _ -> (Name.fromString "a",False)
    in
    case (isValueReferenceToSimpleTypesRecord value ctx.typesContextInfo, valueIsFunctionParameter) of
       (_, (paramName, True)) -> Scala.Ref [paramName |> Name.toCamelCase] simpleFieldName
       (Just (path, refererName), (_, False)) -> Scala.Ref (path ++ [refererName |> Name.toTitleCase]) simpleFieldName
       _ -> Scala.Literal (Scala.StringLit "Field access not converted")


mapVariableAccess : (IrType.Type a) -> Name.Name -> ValueMappingContext -> Scala.Value
mapVariableAccess _ name _ =
   Scala.Variable (name |> Name.toCamelCase)   



mapConstructorAccess : (IrType.Type a) -> FQName.FQName -> ValueMappingContext -> Scala.Value
mapConstructorAccess tpe name ctx =
    case tpe of
        IrType.Reference _ typeName _ ->
            if isUnionTypeWithoutParams typeName ctx.typesContextInfo then
                scalaReferenceToUnionTypeCase typeName name
            else 
                (Scala.Literal (Scala.StringLit "Field access not converted"))
        _ -> (Scala.Literal (Scala.StringLit "Field access not converted"))

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