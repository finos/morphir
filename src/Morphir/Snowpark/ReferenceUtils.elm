module Morphir.Snowpark.ReferenceUtils exposing (
    scalaPathToModule
    , isTypeReferenceToSimpleTypesRecord
    , isValueReferenceToSimpleTypesRecord
    , mapLiteral
    , scalaReferenceToUnionTypeCase
    , getCustomTypeParameterFieldAccess)

import Morphir.IR.Name as Name
import Morphir.IR.Type as IrType
import Morphir.Scala.AST as Scala
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.Snowpark.MappingContext exposing (MappingContextInfo, isRecordWithSimpleTypes)
import Html.Attributes exposing (name)
import Morphir.IR.FQName as FQName
import Morphir.IR.Value exposing (Value(..))
import Morphir.Snowpark.Constants as Constants

scalaPathToModule : FQName.FQName -> Scala.Path
scalaPathToModule name =
    let
        packagePath =  FQName.getPackagePath name |> List.map Name.toCamelCase
        modulePath = case FQName.getModulePath name |> List.reverse of
                        (last::restInverted) -> ((Name.toTitleCase last) :: (List.map Name.toCamelCase restInverted)) |> List.reverse
                        _ -> []
    in
        packagePath ++ modulePath

isValueReferenceToSimpleTypesRecord : (Value ta (IrType.Type a)) -> MappingContextInfo () -> Maybe (Scala.Path, Name.Name)
isValueReferenceToSimpleTypesRecord expression ctx =
   case expression of
       Variable typeReference _ -> 
            isTypeReferenceToSimpleTypesRecord typeReference ctx
       _ -> 
            Nothing


isTypeReferenceToSimpleTypesRecord : (IrType.Type a) -> MappingContextInfo () -> Maybe (Scala.Path, Name.Name)
isTypeReferenceToSimpleTypesRecord typeReference ctx =
    case typeReference of
        IrType.Reference _ typeName _ -> 
            if isRecordWithSimpleTypes typeName ctx then
                Just (scalaPathToModule typeName, (FQName.getLocalName typeName))
            else
                Nothing
        _ -> Nothing


mapLiteral : ta -> Literal -> Scala.Value
mapLiteral _ literal =
    case literal of
                CharLiteral val ->
                    Constants.applySnowparkFunc "lit" [(Scala.Literal (Scala.CharacterLit val))]
                StringLiteral val ->                    
                    Constants.applySnowparkFunc "lit" [(Scala.Literal (Scala.StringLit val))]
                BoolLiteral val ->
                    Constants.applySnowparkFunc "lit" [(Scala.Literal (Scala.BooleanLit val))]
                WholeNumberLiteral val ->
                    Constants.applySnowparkFunc "lit" [(Scala.Literal (Scala.IntegerLit val))]
                FloatLiteral val ->
                    Constants.applySnowparkFunc "lit" [(Scala.Literal (Scala.FloatLit val))]
                _ ->
                    Debug.todo "The type '_' is not implemented"


scalaReferenceToUnionTypeCase : FQName.FQName -> FQName.FQName -> Scala.Value
scalaReferenceToUnionTypeCase typeName constructorName =
    let
        nsName = scalaPathToModule constructorName
        containerObjectName = FQName.getLocalName typeName |> Name.toTitleCase
        containerObjectFieldName = FQName.getLocalName constructorName |> Name.toTitleCase
    in 
    Scala.Ref (nsName ++ [containerObjectName]) containerObjectFieldName

getCustomTypeParameterFieldAccess : Int -> String
getCustomTypeParameterFieldAccess paramIndex =
    "field" ++ (String.fromInt paramIndex)
