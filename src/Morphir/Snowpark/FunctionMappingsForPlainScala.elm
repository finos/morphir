module Morphir.Snowpark.FunctionMappingsForPlainScala exposing (mapFunctionCall, mapValueForPlainScala)

import Dict exposing (Dict)
import Morphir.IR.Value as ValueIR exposing (Pattern(..), Value(..))
import Morphir.IR.Type as TypeIR
import Morphir.IR.Name as Name
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants as Constants
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Snowpark.Operatorsmaps exposing (mapOperator)
import Morphir.Snowpark.MapFunctionsMapping exposing (FunctionMappingTable 
                                                     , IrValueType
                                                     , listFunctionName
                                                     , basicsFunctionName
                                                     , mapUncurriedFunctionCall
                                                     , dataFrameMappings
                                                     , dataFrameMappings)
import Morphir.Snowpark.ReferenceUtils exposing (mapLiteralToPlainLiteral)
import Morphir.Snowpark.LetMapping exposing (mapLetDefinition)
import Morphir.Snowpark.MapExpressionsToDataFrameOperations as MapDfOperations
import Morphir.Snowpark.PatternMatchMapping exposing (PatternMatchValues)
import Morphir.Snowpark.AccessElementMapping exposing (mapReferenceAccess)
import Morphir.Snowpark.MappingContext exposing (isUnionTypeWithoutParams)
import Morphir.IR.FQName as FQName

mapValueForPlainScala : IrValueType () -> ValueMappingContext -> Scala.Value
mapValueForPlainScala value ctx =
    case value of
        Apply _ _ _ ->
            mapFunctionCall value mapValueForPlainScala ctx
        Literal tpe literal ->
            mapLiteralToPlainLiteral tpe literal
        LetDefinition _ name definition body ->
            mapLetDefinition name definition body mapValueForPlainScala ctx
        Reference tpe name ->
            mapReferenceAccess tpe name mapValueForPlainScala ctx
        PatternMatch tpe expr cases ->
            mapPatternMatch (tpe, expr, cases) mapValueForPlainScala ctx
        _ ->
            MapDfOperations.mapValue value ctx

mapPatternMatch :  PatternMatchValues ta -> (Value ta (TypeIR.Type ()) -> ValueMappingContext -> Scala.Value) -> ValueMappingContext -> Scala.Value
mapPatternMatch (tpe, expr, cases) mapValue ctx =
    let
       convertedCases = 
            cases 
                |> List.map (mapCaseOfCase mapValue ctx)
    in
    Scala.Match (mapValue expr ctx) (Scala.MatchCases convertedCases)


mapCaseOfCase : (Value ta (TypeIR.Type ()) -> ValueMappingContext -> Scala.Value) -> ValueMappingContext -> ( Pattern (TypeIR.Type ()), Value ta (TypeIR.Type ()) ) -> (Scala.Pattern, Scala.Value)
mapCaseOfCase mapValue ctx (sourcePattern, sourceExpr) =
    let
       convertedExpr = mapValue sourceExpr ctx
    in
    case sourcePattern of
        (ConstructorPattern _ ([["morphir"],["s","d","k"]],[["maybe"]],["just"]) [ AsPattern _ (WildcardPattern _) varName]) ->
            (Scala.UnapplyMatch [] "Some" [ (Scala.NamedMatch (Name.toCamelCase varName)) ], convertedExpr)
        (ConstructorPattern _ ([["morphir"],["s","d","k"]],[["maybe"]],["nothing"]) []) ->
            (Scala.UnapplyMatch [] "None" [], convertedExpr)
        (ConstructorPattern (TypeIR.Reference _ fullTypeName _) fullName []) ->
            if isUnionTypeWithoutParams fullTypeName ctx.typesContextInfo then
                (Scala.LiteralMatch (Scala.StringLit (Name.toTitleCase (FQName.getLocalName fullName))), convertedExpr)
            else
                (Scala.NamedMatch "CONSTRUCTOR_PATTERN_NOT_CONVERTED", convertedExpr)
        _ -> 
            (Scala.NamedMatch "PATTERN_NOT_CONVERTED", convertedExpr)
                


mapFunctionCall : ValueIR.Value () (TypeIR.Type ()) -> Constants.MapValueType () -> ValueMappingContext -> Scala.Value
mapFunctionCall value mapValue ctx =
    case value of
        ValueIR.Apply _ func arg ->
                mapUncurriedFunctionCall (ValueIR.uncurryApply func arg) mapValue actualMappingTable ctx
        _ ->
            Scala.Literal (Scala.StringLit "invalid function call")

mergeMappingDictionaries : FunctionMappingTable ta ->  FunctionMappingTable ta -> FunctionMappingTable ta
mergeMappingDictionaries first second =
    Dict.union first second
   
specificMappings : FunctionMappingTable ta
specificMappings =
    [
        ( listFunctionName [ "range" ], mapListRangeFunction ) 
        , ( listFunctionName [ "map" ], mapListMapFunction ) 
        , ( listFunctionName [ "sum" ], mapListSumFunction )  
        , ( listFunctionName [ "maximum" ], mapListMaximumFunction )
        , ( basicsFunctionName [ "negate" ], mapNegateFunction )
        , ( basicsFunctionName [ "max" ], mapMaxMinFunction "max" )
        , ( basicsFunctionName [ "min" ], mapMaxMinFunction "min" )
    ]
        |> Dict.fromList

actualMappingTable : FunctionMappingTable ta
actualMappingTable = mergeMappingDictionaries specificMappings dataFrameMappings

mapListRangeFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListRangeFunction ( _, args ) mapValue ctx =
    case args of    
        [ start, end ] ->
            let
                mappedStart = mapValue start ctx
                mappedEnd = Scala.BinOp (mapValue end ctx) "+" (Scala.Literal (Scala.IntegerLit 1))
            in
            Scala.Apply (Scala.Select (Scala.Variable "Seq") "range") [ Scala.ArgValue Nothing mappedStart, Scala.ArgValue Nothing mappedEnd]
        _ ->
            Scala.Literal (Scala.StringLit "List range scenario not supported")

mapListMapFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListMapFunction ( _, args ) mapValue ctx =
    case args of    
        [ action, collection ] ->
            let
                mappedStart = mapMapPredicate action mapValue ctx
                mappedEnd = mapValue collection ctx
            in
            Scala.Apply (Scala.Select mappedEnd "map") [ Scala.ArgValue Nothing mappedStart]
        _ ->
            Scala.Literal (Scala.StringLit "List map scenario not supported")

mapListSumFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListSumFunction ( _, args ) mapValue ctx =
    case args of    
        [ collection ] ->
             let
                mappedCollection = mapValue collection ctx
            in
            Scala.Apply (Scala.Select mappedCollection "reduce") [ Scala.ArgValue Nothing (Scala.BinOp (Scala.Wildcard) "+" (Scala.Wildcard)) ] 
        _ ->
            Scala.Literal (Scala.StringLit "List sum scenario not supported")

mapListMaximumFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListMaximumFunction ( _, args ) mapValue ctx =
    case args of    
        [ collection ] ->
             let
                mappedCollection = mapValue collection ctx
            in
            Scala.Apply (Scala.Select mappedCollection "reduceOption") 
                        [ Scala.ArgValue Nothing (Scala.BinOp (Scala.Wildcard) "max" (Scala.Wildcard)) ] 
        _ ->
            Scala.Literal (Scala.StringLit "List maximum scenario not supported")


mapNegateFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapNegateFunction ( _, args ) mapValue ctx =
    case args of    
        [ value ] ->
             let
                mappedValue = mapValue value ctx
            in
            Scala.UnOp "-" mappedValue
        _ ->
            Scala.Literal (Scala.StringLit "negate scenario not supported")

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

mapMaxMinFunction : String -> (IrValueType ta, List (IrValueType ta))  -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapMaxMinFunction name ( _, args ) mapValue ctx =
    case args of    
        [ value1, value2 ] ->
             let
                mappedValue1 = adjustIntegerFloatLiteral (mapValue value1 ctx)
                mappedValue2 = adjustIntegerFloatLiteral (mapValue value2 ctx)
            in
            Scala.BinOp mappedValue1 name mappedValue2
        _ ->
            Scala.Literal (Scala.StringLit (name ++ "scenario not supported"))


mapMapPredicate : Value ta (TypeIR.Type ()) -> (Constants.MapValueType ta) -> ValueMappingContext -> Scala.Value
mapMapPredicate action mapValue ctx =
    case action of
        ValueIR.Lambda _ (ValueIR.AsPattern _ (ValueIR.WildcardPattern _) lmdarg) body ->
            Scala.Lambda [ ((Name.toCamelCase lmdarg) , Nothing) ] (mapValue body ctx)
        _ ->
            mapValue action ctx



mapForOperatorCall : Name.Name -> Value ta (TypeIR.Type ()) -> Value ta (TypeIR.Type ()) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapForOperatorCall optname left right mapValue ctx =
    let
        leftValue = mapValue left ctx
        rightValue = mapValue right ctx
        operatorname = mapOperator optname
    in
    Scala.BinOp leftValue operatorname rightValue
            