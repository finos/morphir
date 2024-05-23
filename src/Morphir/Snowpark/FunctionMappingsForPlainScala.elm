module Morphir.Snowpark.FunctionMappingsForPlainScala exposing (mapFunctionCall, mapValueForPlainScala)

import Dict
import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Type as TypeIR
import Morphir.IR.Value as ValueIR exposing (Pattern(..), TypedValue, Value(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.AccessElementMapping exposing (mapReferenceAccess)
import Morphir.Snowpark.Constants as Constants exposing (ValueGenerationResult)
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue)
import Morphir.Snowpark.LetMapping exposing (mapLetDefinition)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations as MapDfOperations
import Morphir.Snowpark.MapFunctionsMapping
    exposing
        ( FunctionMappingTable
        , basicsFunctionName
        , dataFrameMappings
        , listFunctionName
        , mapUncurriedFunctionCall
        )
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext, isCandidateForDataFrame, isUnionTypeWithoutParams)
import Morphir.Snowpark.Operatorsmaps exposing (mapOperator)
import Morphir.Snowpark.PatternMatchMapping exposing (PatternMatchValues)
import Morphir.Snowpark.ReferenceUtils exposing (curryCall, errorValueAndIssue, mapLiteralToPlainLiteral)


mapValueForPlainScala : TypedValue -> ValueMappingContext -> ValueGenerationResult
mapValueForPlainScala value ctx =
    case value of
        Apply _ _ _ ->
            mapFunctionCall value mapValueForPlainScala ctx

        Literal tpe literal ->
            ( mapLiteralToPlainLiteral tpe literal, [] )

        LetDefinition _ name definition body ->
            mapLetDefinition name definition body mapValueForPlainScala ctx

        Reference tpe name ->
            mapReferenceAccess tpe name mapValueForPlainScala ctx

        PatternMatch tpe expr cases ->
            mapPatternMatch ( tpe, expr, cases ) mapValueForPlainScala ctx

        _ ->
            MapDfOperations.mapValue value ctx


mapPatternMatch : PatternMatchValues -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapPatternMatch ( tpe, expr, cases ) mapValue ctx =
    let
        ( convertedCases, casesIssues ) =
            cases
                |> List.map (mapCaseOfCase mapValue ctx)
                |> List.unzip

        ( mappedExpr, exprIssues ) =
            mapValue expr ctx
    in
    ( Scala.Match mappedExpr (Scala.MatchCases convertedCases), exprIssues ++ List.concat casesIssues )


mapCaseOfCase : Constants.MapValueType -> ValueMappingContext -> ( Pattern (TypeIR.Type ()), TypedValue ) -> ( ( Scala.Pattern, Scala.Value ), List GenerationIssue )
mapCaseOfCase mapValue ctx ( sourcePattern, sourceExpr ) =
    let
        ( convertedExpr, convertedExprIssues ) =
            mapValue sourceExpr ctx
    in
    case sourcePattern of
        ConstructorPattern _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) [ AsPattern _ (WildcardPattern _) varName ] ->
            ( ( Scala.UnapplyMatch [] "Some" [ Scala.NamedMatch (Name.toCamelCase varName) ], convertedExpr ), convertedExprIssues )

        ConstructorPattern _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ] ) [] ->
            ( ( Scala.UnapplyMatch [] "None" [], convertedExpr ), convertedExprIssues )

        ConstructorPattern (TypeIR.Reference _ fullTypeName _) fullName [] ->
            if isUnionTypeWithoutParams fullTypeName ctx.typesContextInfo then
                ( ( Scala.LiteralMatch (Scala.StringLit (Name.toTitleCase (FQName.getLocalName fullName))), convertedExpr ), convertedExprIssues )

            else
                ( ( Scala.NamedMatch "CONSTRUCTOR_PATTERN_NOT_CONVERTED", convertedExpr )
                , "Constructor pattern not support for Scala function" :: convertedExprIssues
                )

        _ ->
            ( ( Scala.NamedMatch "PATTERN_NOT_CONVERTED", convertedExpr )
            , "Pattern not generated for Scala function" :: convertedExprIssues
            )


mapFunctionCall : ValueIR.Value () (TypeIR.Type ()) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapFunctionCall value mapValue ctx =
    case value of
        ValueIR.Apply _ func arg ->
            mapUncurriedFunctionCall (ValueIR.uncurryApply func arg) mapValue actualMappingTable ctx

        _ ->
            errorValueAndIssue "invalid function call"


mergeMappingDictionaries : FunctionMappingTable -> FunctionMappingTable -> FunctionMappingTable
mergeMappingDictionaries first second =
    Dict.union first second


specificMappings : FunctionMappingTable
specificMappings =
    [ ( listFunctionName [ "range" ], mapListRangeFunction )
    , ( listFunctionName [ "map" ], mapListMapFunction )
    , ( listFunctionName [ "sum" ], mapListSumFunction )
    , ( listFunctionName [ "maximum" ], mapListMaximumFunction )
    , ( basicsFunctionName [ "negate" ], mapNegateFunction )
    , ( basicsFunctionName [ "max" ], mapMaxMinFunction "max" )
    , ( basicsFunctionName [ "min" ], mapMaxMinFunction "min" )
    , ( basicsFunctionName [ "to", "float" ], mapToFloatFunctionCall )
    ]
        |> Dict.fromList


actualMappingTable : FunctionMappingTable
actualMappingTable =
    mergeMappingDictionaries specificMappings dataFrameMappings


mapListRangeFunction : ( TypedValue, List TypedValue ) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListRangeFunction ( _, args ) mapValue ctx =
    case args of
        [ start, end ] ->
            let
                ( mappedStart, startIssues ) =
                    mapValue start ctx

                ( mappedEnd, endIssues ) =
                    mapValue end ctx

                endExpr =
                    Scala.BinOp mappedEnd "+" (Scala.Literal (Scala.IntegerLit 1))
            in
            ( Scala.Apply (Scala.Select (Scala.Variable "Seq") "range") [ Scala.ArgValue Nothing mappedStart, Scala.ArgValue Nothing endExpr ]
            , startIssues ++ endIssues
            )

        _ ->
            errorValueAndIssue "List range scenario not supported"


mapListMapFunction : ( TypedValue, List TypedValue ) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListMapFunction (( _, args ) as call) mapValue ctx =
    case args of
        [ action, collection ] ->
            if isCandidateForDataFrame (ValueIR.valueAttribute collection) ctx.typesContextInfo then
                MapDfOperations.mapValue (curryCall call) ctx

            else
                let
                    ( mappedStart, startIssues ) =
                        mapMapPredicate action mapValue ctx

                    ( mappedEnd, endIssues ) =
                        mapValue collection ctx
                in
                ( Scala.Apply (Scala.Select mappedEnd "map") [ Scala.ArgValue Nothing mappedStart ], startIssues ++ endIssues )

        _ ->
            errorValueAndIssue "List map scenario not supported"


mapListSumFunction : ( TypedValue, List TypedValue ) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListSumFunction (( _, args ) as call) mapValue ctx =
    let
        collectionComesFromDataFrameProjection : TypedValue -> Bool
        collectionComesFromDataFrameProjection collection =
            case collection of
                ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "map" ] )) _) innerCollection ->
                    isCandidateForDataFrame (ValueIR.valueAttribute innerCollection) ctx.typesContextInfo

                _ ->
                    False
    in
    case args of
        [ collection ] ->
            if collectionComesFromDataFrameProjection collection then
                MapDfOperations.mapValue (curryCall call) ctx

            else
                let
                    ( mappedCollection, collectionIssues ) =
                        mapValue collection ctx
                in
                ( Scala.Apply (Scala.Select mappedCollection "reduce") [ Scala.ArgValue Nothing (Scala.BinOp Scala.Wildcard "+" Scala.Wildcard) ]
                , collectionIssues
                )

        _ ->
            errorValueAndIssue "List sum scenario not supported"


mapListMaximumFunction : ( TypedValue, List TypedValue ) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListMaximumFunction ( _, args ) mapValue ctx =
    case args of
        [ collection ] ->
            let
                ( mappedCollection, collectionIssues ) =
                    mapValue collection ctx
            in
            ( Scala.Apply (Scala.Select mappedCollection "reduceOption")
                [ Scala.ArgValue Nothing (Scala.BinOp Scala.Wildcard "max" Scala.Wildcard) ]
            , collectionIssues
            )

        _ ->
            errorValueAndIssue "List maximum scenario not supported"


mapNegateFunction : ( TypedValue, List TypedValue ) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapNegateFunction ( _, args ) mapValue ctx =
    case args of
        [ value ] ->
            let
                ( mappedValue, valueIssues ) =
                    mapValue value ctx
            in
            ( Scala.UnOp "-" mappedValue, valueIssues )

        _ ->
            errorValueAndIssue "negate scenario not supported"


adjustIntegerFloatLiteral : Scala.Value -> Scala.Value
adjustIntegerFloatLiteral value =
    case value of
        Scala.Literal (Scala.FloatLit innerValue) ->
            if innerValue == (floor >> toFloat) innerValue then
                Scala.Select value "toDouble"

            else
                value

        _ ->
            value


mapMaxMinFunction : String -> ( TypedValue, List TypedValue ) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapMaxMinFunction name ( _, args ) mapValue ctx =
    case args of
        [ value1, value2 ] ->
            let
                ( mappedValue1, value1Issues ) =
                    mapValue value1 ctx

                ( mappedValue2, value2Issues ) =
                    mapValue value2 ctx
            in
            ( Scala.BinOp (adjustIntegerFloatLiteral mappedValue1) name (adjustIntegerFloatLiteral mappedValue2)
            , value1Issues ++ value2Issues
            )

        _ ->
            errorValueAndIssue (name ++ "scenario not supported")


mapMapPredicate : TypedValue -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapMapPredicate action mapValue ctx =
    case action of
        ValueIR.Lambda _ (ValueIR.AsPattern _ (ValueIR.WildcardPattern _) lmdarg) body ->
            let
                ( generatedBody, bodyIssues ) =
                    mapValue body ctx
            in
            ( Scala.Lambda [ ( Name.toCamelCase lmdarg, Nothing ) ] generatedBody, bodyIssues )

        _ ->
            mapValue action ctx


mapForOperatorCall : Name.Name -> TypedValue -> TypedValue -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapForOperatorCall optname left right mapValue ctx =
    let
        ( leftValue, leftValueIssues ) =
            mapValue left ctx

        ( rightValue, rightValueIssues ) =
            mapValue right ctx

        operatorname =
            mapOperator optname
    in
    ( Scala.BinOp leftValue operatorname rightValue
    , leftValueIssues ++ rightValueIssues
    )


mapToFloatFunctionCall : ( TypedValue, List TypedValue ) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapToFloatFunctionCall ( _, args ) mapValue ctx =
    case args of
        [ value ] ->
            let
                ( mappedValue, valueIssues ) =
                    mapValue value ctx
            in
            ( Scala.Select mappedValue "toDouble", valueIssues )

        _ ->
            errorValueAndIssue "`toFloat` scenario not supported"
