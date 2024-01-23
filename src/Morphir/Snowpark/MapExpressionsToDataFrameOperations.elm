module Morphir.Snowpark.MapExpressionsToDataFrameOperations exposing (mapValue)

import Dict
import List
import Morphir.IR.AccessControlled exposing (Access(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), TypedValue, Value(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.AccessElementMapping
    exposing
        ( mapConstructorAccess
        , mapFieldAccess
        , mapReferenceAccess
        , mapVariableAccess
        )
import Morphir.Snowpark.Constants as Constants exposing (ValueGenerationResult, applySnowparkFunc)
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue)
import Morphir.Snowpark.LetMapping exposing (mapLetDefinition)
import Morphir.Snowpark.MapFunctionsMapping as MapFunctionsMapping
import Morphir.Snowpark.MappingContext as MappingContext
    exposing
        ( FunctionClassification(..)
        , ValueMappingContext
        , getFieldInfoIfRecordType
        , isAnonymousRecordWithSimpleTypes
        , isFunctionClassificationReturningDataFrameExpressions
        , isTypeRefToRecordWithComplexTypes
        , isTypeRefToRecordWithSimpleTypes
        , typeRefIsListOf
        )
import Morphir.Snowpark.PatternMatchMapping exposing (mapPatternMatch)
import Morphir.Snowpark.ReferenceUtils
    exposing
        ( errorValueAndIssue
        , getListTypeParameter
        , isTypeReferenceToSimpleTypesRecord
        , mapLiteral
        , scalaPathToModule
        )
import Morphir.Snowpark.Utils exposing (collectMaybeList)


mapValue : TypedValue -> ValueMappingContext -> ( Scala.Value, List GenerationIssue )
mapValue value ctx =
    case value of
        Literal tpe literal ->
            ( mapLiteral tpe literal, [] )

        Field tpe val name ->
            mapFieldAccess tpe val name ctx mapValue

        (Variable _ name) as varAccess ->
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
            mapPatternMatch ( tpe, expr, cases ) mapValue ctx

        IfThenElse _ condition thenExpr elseExpr ->
            mapIfThenElse condition thenExpr elseExpr ctx

        LetDefinition _ name definition body ->
            mapLetDefinition name definition body mapValue ctx

        FieldFunction _ name ->
            ( Constants.applySnowparkFunc "col" [ Scala.Literal (Scala.StringLit (Name.toCamelCase name)) ], [] )

        Value.Tuple _ tupleElements ->
            mapTuple tupleElements ctx

        Value.Record tpe fields ->
            mapRecordCreation tpe fields ctx

        Value.UpdateRecord tpe rec fieldUpdates ->
            mapUpdateRecord tpe rec fieldUpdates ctx

        _ ->
            errorValueAndIssue "Unsupported value element not generated"


mapUpdateRecord : Type () -> TypedValue -> Dict.Dict Name.Name TypedValue -> ValueMappingContext -> ( Scala.Value, List GenerationIssue )
mapUpdateRecord recordType recordExpr fieldUpdates ctx =
    if
        isTypeRefToRecordWithSimpleTypes recordType ctx.typesContextInfo
            || isAnonymousRecordWithSimpleTypes recordType ctx.typesContextInfo
    then
        getFieldInfoIfRecordType recordType ctx.typesContextInfo
            |> Maybe.map
                (\fields ->
                    let
                        ( mappedFields, fieldsIssues ) =
                            fields
                                |> List.map
                                    (\( field, fieldType ) ->
                                        Dict.get field fieldUpdates
                                            |> Maybe.map (\updateExpr -> mapValue updateExpr ctx)
                                            |> Maybe.withDefault (mapValue (Value.Field fieldType recordExpr field) ctx)
                                    )
                                |> List.unzip
                    in
                    ( applySnowparkFunc
                        "array_construct"
                        mappedFields
                    , List.concat fieldsIssues
                    )
                )
            |> Maybe.withDefault (errorValueAndIssue "Unsupported `update record` scenario")

    else
        errorValueAndIssue "Unsupported `update record` scenario"


mapTuple : List TypedValue -> ValueMappingContext -> ValueGenerationResult
mapTuple tupleElements ctx =
    let
        ( args, issues ) =
            tupleElements
                |> List.map (\e -> mapValue e ctx)
                |> List.unzip
    in
    ( Constants.applySnowparkFunc "array_construct" args, List.concat issues )


mapRecordCreation : Type () -> Dict.Dict Name.Name TypedValue -> ValueMappingContext -> ValueGenerationResult
mapRecordCreation tpe fields ctx =
    if isTypeRefToRecordWithComplexTypes tpe ctx.typesContextInfo then
        mapRecordCreationToCaseClassCreation tpe fields ctx

    else if
        (isTypeRefToRecordWithSimpleTypes tpe ctx.typesContextInfo
            || isAnonymousRecordWithSimpleTypes tpe ctx.typesContextInfo
        )
            && isFunctionClassificationReturningDataFrameExpressions ctx.currentFunctionClassification
    then
        MappingContext.getFieldInfoIfRecordType tpe ctx.typesContextInfo
            |> Maybe.map
                (\fieldInfo ->
                    collectMaybeList
                        (\( fieldName, _ ) ->
                            Dict.get fieldName fields
                                |> Maybe.map (\argExpr -> mapValue argExpr ctx)
                        )
                        fieldInfo
                )
            |> Maybe.withDefault Nothing
            |> Maybe.map List.unzip
            |> Maybe.map (\( args, issues ) -> ( applySnowparkFunc "array_construct" args, List.concat issues ))
            |> Maybe.withDefault (errorValueAndIssue "Record creation not generated: could not get information about record.")

    else
        errorValueAndIssue "Record creation not converted"


mapRecordCreationToCaseClassCreation : Type () -> Dict.Dict Name.Name TypedValue -> ValueMappingContext -> ValueGenerationResult
mapRecordCreationToCaseClassCreation tpe fields ctx =
    case tpe of
        Type.Reference _ fullName [] ->
            let
                caseClassReference =
                    Scala.Ref (scalaPathToModule fullName) (fullName |> FQName.getLocalName |> Name.toTitleCase)

                processArg : Name.Name -> TypedValue -> ( Scala.ArgValue, List GenerationIssue )
                processArg fieldName argValue =
                    let
                        ( mappedExpr, issues ) =
                            mapValue argValue ctx
                    in
                    ( Scala.ArgValue (Just (Name.toCamelCase fieldName)) mappedExpr, issues )

                processArgs : List ( Name.Name, Type () ) -> Maybe (List ( Scala.ArgValue, List GenerationIssue ))
                processArgs fieldsInfo =
                    fieldsInfo
                        |> collectMaybeList
                            (\( fieldName, _ ) ->
                                Dict.get fieldName fields
                                    |> Maybe.map (processArg fieldName)
                            )
            in
            MappingContext.getFieldInfoIfRecordType tpe ctx.typesContextInfo
                |> Maybe.map processArgs
                |> Maybe.withDefault Nothing
                |> Maybe.map List.unzip
                |> Maybe.map (\( ctorArgs, issues ) -> ( Scala.Apply caseClassReference ctorArgs, List.concat issues ))
                |> Maybe.withDefault (errorValueAndIssue ("Record creation not converted: " ++ FQName.toString fullName))

        _ ->
            errorValueAndIssue "Record creation not converted"


mapListCreation : Type () -> List TypedValue -> ValueMappingContext -> ValueGenerationResult
mapListCreation tpe values ctx =
    let
        listOfRecordWithSimpleTypes =
            typeRefIsListOf tpe (\innerTpe -> isTypeRefToRecordWithSimpleTypes innerTpe ctx.typesContextInfo)
    in
    if
        listOfRecordWithSimpleTypes
            && isFunctionClassificationReturningDataFrameExpressions ctx.currentFunctionClassification
    then
        let
            ( mappedValues, valuesIssues ) =
                values
                    |> List.map (\v -> mapLiteralListValue v ctx)
                    |> List.unzip
        in
        ( applySnowparkFunc "array_construct" mappedValues, List.concat valuesIssues )

    else
        case
            ( getListTypeParameter tpe
                |> Maybe.map (\t -> isTypeReferenceToSimpleTypesRecord t ctx.typesContextInfo)
                |> Maybe.withDefault Nothing
            , values
            )
        of
            ( Just ( path, name ), [] ) ->
                ( Scala.Apply
                    (Scala.Select
                        (Scala.Ref path (Name.toTitleCase name))
                        "createEmptyDataFrame"
                    )
                    [ Scala.ArgValue Nothing (Scala.Variable "sfSession") ]
                , []
                )

            _ ->
                let
                    ( mappedValues, valuesIssues ) =
                        values
                            |> List.map (\v -> mapValue v ctx)
                            |> List.unzip
                in
                ( Scala.Apply
                    (Scala.Variable "Seq")
                    (mappedValues |> List.map (Scala.ArgValue Nothing))
                , List.concat valuesIssues
                )


mapLiteralListValue : TypedValue -> ValueMappingContext -> ValueGenerationResult
mapLiteralListValue value ctx =
    let
        ( mappedValue, issues ) =
            mapValue value ctx
    in
    case value of
        Value.Variable _ _ ->
            generateReplacementForDataFrameItemVariable mappedValue value ctx
                |> Maybe.map (\result -> ( result, issues ))
                |> Maybe.withDefault ( mappedValue, issues )

        _ ->
            ( mappedValue, issues )


generateReplacementForDataFrameItemVariable : Scala.Value -> TypedValue -> ValueMappingContext -> Maybe Scala.Value
generateReplacementForDataFrameItemVariable replacement nameAccess ctx =
    getFieldInfoIfRecordType (Value.valueAttribute nameAccess) ctx.typesContextInfo
        |> Maybe.map
            (\fields ->
                let
                    args =
                        fields
                            |> List.map
                                (\( name, _ ) ->
                                    Scala.Select replacement (Name.toCamelCase name)
                                )
                in
                applySnowparkFunc "array_construct" args
            )


mapIfThenElse : TypedValue -> TypedValue -> TypedValue -> ValueMappingContext -> ValueGenerationResult
mapIfThenElse condition thenExpr elseExpr ctx =
    let
        ( mappedCondition, conditionIssues ) =
            mapValue condition ctx

        ( mappedThen, thenIssues ) =
            mapValue thenExpr ctx

        ( mappedElse, elseIssues ) =
            mapValue elseExpr ctx

        whenCall =
            Constants.applySnowparkFunc "when" [ mappedCondition, mappedThen ]
    in
    ( Scala.Apply (Scala.Select whenCall "otherwise") [ Scala.ArgValue Nothing mappedElse ]
    , conditionIssues ++ thenIssues ++ elseIssues
    )
