module Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)

import Dict
import List
import Morphir.IR.AccessControlled exposing (Access(..))
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type)
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.Constants as Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.AccessElementMapping exposing (
    mapFieldAccess
    , mapReferenceAccess
    , mapVariableAccess
    , mapConstructorAccess)
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord, mapLiteral, isTypeReferenceToSimpleTypesRecord)
import Morphir.Snowpark.MapFunctionsMapping as MapFunctionsMapping
import Morphir.Snowpark.PatternMatchMapping exposing (mapPatternMatch)
import Morphir.Snowpark.MappingContext as MappingContext exposing (
             typeRefIsListOf
            , ValueMappingContext
            , isFunctionClassificationReturningDataFrameExpressions
            , isTypeRefToRecordWithSimpleTypes
            , isTypeRefToRecordWithComplexTypes )
import Morphir.Snowpark.ReferenceUtils exposing (scalaPathToModule)
import Morphir.Snowpark.Utils exposing (collectMaybeList)
import Morphir.Snowpark.MappingContext exposing (isAnonymousRecordWithSimpleTypes)
import Morphir.IR.Name as Name
import Morphir.Snowpark.ReferenceUtils exposing (getListTypeParameter)
import Morphir.Snowpark.MappingContext exposing (FunctionClassification(..))
import Morphir.Snowpark.LetMapping exposing (mapLetDefinition)

mapValue : Value () (Type ()) -> ValueMappingContext -> Scala.Value
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
            mapReferenceAccess tpe name mapValue ctx
        Apply _ _ _ ->
            MapFunctionsMapping.mapFunctionsMapping value mapValue ctx
        PatternMatch tpe expr cases ->
            mapPatternMatch (tpe, expr, cases) mapValue ctx
        IfThenElse _ condition thenExpr elseExpr ->
            mapIfThenElse condition thenExpr elseExpr ctx
        LetDefinition _ name definition body ->
            mapLetDefinition name definition body mapValue ctx
        FieldFunction _ name ->
            Constants.applySnowparkFunc "col" [(Scala.Literal (Scala.StringLit (Name.toCamelCase name)))]
        Value.Tuple _ tupleElements ->
            Constants.applySnowparkFunc "array_construct" <| List.map (\e -> mapValue e ctx) tupleElements
        Value.Record tpe fields ->
            mapRecordCreation tpe fields ctx
        _ ->
            Scala.Literal (Scala.StringLit ("Unsupported element"))


mapRecordCreation : Type () -> Dict.Dict (Name.Name) (Value () (Type ())) -> ValueMappingContext -> Scala.Value
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


mapRecordCreationToCaseClassCreation : Type () -> Dict.Dict (Name.Name) (Value () (Type ())) -> ValueMappingContext -> Scala.Value
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

mapListCreation : (Type ()) -> List (Value () (Type ())) -> ValueMappingContext -> Scala.Value
mapListCreation tpe values ctx =
    let
        listOfRecordWithSimpleTypes = typeRefIsListOf tpe (\innerTpe -> isTypeRefToRecordWithSimpleTypes innerTpe ctx.typesContextInfo)
    in
    if listOfRecordWithSimpleTypes &&
       isFunctionClassificationReturningDataFrameExpressions ctx.currentFunctionClassification then
       applySnowparkFunc "array_construct"
            (values |> List.map (\v -> mapValue v ctx))
    else
        case (getListTypeParameter tpe |> Maybe.map (\t -> isTypeReferenceToSimpleTypesRecord t ctx.typesContextInfo) |> Maybe.withDefault Nothing, values) of
            (Just (path, name), []) ->
                Scala.Apply (Scala.Select (Scala.Ref path (Name.toTitleCase name)) "createEmptyDataFrame") [ Scala.ArgValue Nothing (Scala.Variable "sfSession") ]
            _ ->
                Scala.Apply 
                    (Scala.Variable "Seq")
                    (values |> List.map (\v -> Scala.ArgValue Nothing (mapValue v ctx)))

mapIfThenElse : Value () (Type ()) -> Value () (Type ()) -> Value () (Type ()) -> ValueMappingContext -> Scala.Value
mapIfThenElse condition thenExpr elseExpr ctx =
   let
       whenCall = 
            Constants.applySnowparkFunc "when" [ mapValue condition ctx,  mapValue thenExpr ctx ]
   in
   Scala.Apply (Scala.Select whenCall "otherwise") [Scala.ArgValue Nothing (mapValue elseExpr ctx)]
