module Morphir.Snowpark.PatternMatchMapping exposing (..)

{-| Generation for `PatternMatch` expressions
   
-}

import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value, Pattern(..))
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Scala.AST as Scala
import Morphir.IR.Literal exposing (Literal)
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.ReferenceUtils exposing (mapLiteral
           , scalaReferenceToUnionTypeCase)
import Morphir.IR.Value as Value
import Morphir.Snowpark.MappingContext exposing (isUnionTypeRefWithoutParams)
import Morphir.IR.Type as Type

type alias PatternMatchValues ta = (Type (), Value ta (Type ()), List ( Pattern (Type ()), Value ta (Type ()) ))

equalExpr : Scala.Value -> Scala.Value -> Scala.Value
equalExpr left right = Scala.BinOp left "===" right

createChainOfWhenCalls : (Scala.Value, Scala.Value) -> List (Scala.Value, Scala.Value) -> Scala.Value
createChainOfWhenCalls (firstCondition, firstValue) restConditionActionPairs =
    List.foldr 
        (\(condition, resultExpr) accumulated ->
            Scala.Apply (Scala.Select accumulated "when") [Scala.ArgValue Nothing condition, Scala.ArgValue Nothing resultExpr] )
        (applySnowparkFunc "when" [firstCondition, firstValue]) 
        restConditionActionPairs


createChainOfWhenWithOtherwise : (Scala.Value, Scala.Value) -> List (Scala.Value, Scala.Value) -> Scala.Value -> Scala.Value
createChainOfWhenWithOtherwise first restConditionActionPairs defaultValue =
   let
      whenCalls = createChainOfWhenCalls first restConditionActionPairs 
   in 
   Scala.Apply (Scala.Select whenCalls "otherwise") [Scala.ArgValue Nothing defaultValue]

mapPatternMatch :  PatternMatchValues ta -> (Value ta (Type ()) -> ValueMappingContext -> Scala.Value) -> ValueMappingContext -> Scala.Value
mapPatternMatch (tpe, expr, cases) mapValue ctx =
    case classifyScenario expr cases ctx of
        LiteralsWithDefault ((firstLit, firstExpr)::rest) defaultValue ->
            let
                compareWithExpr =  equalExpr (mapValue expr ctx)
                litExpr = mapLiteral () firstLit
                restPairs = rest |> List.map (\(lit, val) -> (compareWithExpr (mapLiteral () lit), (mapValue val ctx)))
            in
            createChainOfWhenWithOtherwise ((compareWithExpr litExpr), mapValue firstExpr ctx) restPairs (mapValue defaultValue ctx)
        UnionTypesWithoutParams ((firstConstr, firstExpr)::rest) (Just defaultValue) ->
            let
                compareWithExpr =  equalExpr (mapValue expr ctx)
                
                restPairs = rest |> List.map (\(constr, val) -> (compareWithExpr constr, (mapValue val ctx)))
            in
            createChainOfWhenWithOtherwise (compareWithExpr firstConstr, mapValue firstExpr ctx) restPairs (mapValue defaultValue ctx)
        UnionTypesWithoutParams ((firstConstr, firstExpr)::rest) Nothing ->
            let
                compareWithExpr =  equalExpr (mapValue expr ctx)
                
                restPairs = rest |> List.map (\(constr, val) -> (compareWithExpr constr, (mapValue val ctx)))
            in
            createChainOfWhenCalls (compareWithExpr firstConstr, mapValue firstExpr ctx) restPairs
        _ ->
            Scala.Variable "NOT_CONVERTED"

type PatternMatchScenario ta
    = LiteralsWithDefault (List (Literal, Value ta (Type ()))) (Value ta (Type ()))
    | UnionTypesWithoutParams (List (Scala.Value, Value ta (Type ()))) (Maybe (Value ta (Type ())))
    | Unsupported

collectMaybeList : (a -> Maybe b) -> List a -> Maybe (List b)
collectMaybeList action aList =
    collectMaybeListAux action aList []

collectMaybeListAux : (a -> Maybe b) -> List a -> List b -> Maybe (List b)
collectMaybeListAux action aList current =
    case aList of
        first::rest ->
            (action first)
                 |> Maybe.map (\newFirst -> collectMaybeListAux action rest (newFirst::current)) 
                 |> Maybe.withDefault Nothing
        [] ->
            Just current


checkForLiteralCase : ( Pattern (Type ()), Value ta (Type ()) ) -> Maybe (Literal, Value ta (Type ()))
checkForLiteralCase (pattern, caseValue) = 
   case pattern of
        (LiteralPattern _ literal) -> 
            Just (literal, caseValue)
        _ -> 
            Nothing

checkLiteralsWithDefault : List ( Pattern (Type ()), Value ta (Type ()) ) -> (Maybe ((List (Literal, Value ta (Type ()))), (Value ta (Type ()))))
checkLiteralsWithDefault cases =
   case List.reverse cases of
        ((WildcardPattern _, wildCardResult)::restReversed) -> 
            (collectMaybeList checkForLiteralCase restReversed) |> Maybe.map (\p -> (p, wildCardResult))
        _ -> 
            Nothing

checkForUnionOfWithNoParams : ( Pattern (Type ()), Value ta (Type ()) ) -> Maybe (Scala.Value, Value ta (Type ()))
checkForUnionOfWithNoParams (pattern, caseValue) = 
   case pattern of
        (ConstructorPattern (Type.Reference _ typeName _) name []) -> 
            Just (scalaReferenceToUnionTypeCase typeName name, caseValue)
        _ -> 
            Nothing


checkUnionWithNoParamsWithDefault : Value ta (Type ()) -> List ( Pattern (Type ()), Value ta (Type ()) ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
checkUnionWithNoParamsWithDefault expr cases ctx =
    if isUnionTypeRefWithoutParams (Value.valueAttribute expr) ctx.typesContextInfo  then
        case List.reverse cases of
            ((WildcardPattern _, wildCardResult)::restReversed) -> 
                (collectMaybeList checkForUnionOfWithNoParams restReversed) 
                     |> Maybe.map (\p -> (UnionTypesWithoutParams p (Just wildCardResult)))
            ((ConstructorPattern _ _ [], _)::_) as constructorCases ->
                (collectMaybeList checkForUnionOfWithNoParams constructorCases) 
                     |> Maybe.map (\p -> (UnionTypesWithoutParams p Nothing))
            _ -> 
                Nothing
    else 
        Nothing
tryAlternative : Maybe a -> (() -> Maybe a) -> Maybe a
tryAlternative currentResult nextAction =
    case currentResult of
        Nothing -> 
            nextAction ()
        _ -> 
            currentResult

classifyScenario : (Value ta (Type ())) -> List (Pattern (Type ()), Value ta (Type ())) -> ValueMappingContext -> PatternMatchScenario ta
classifyScenario value cases ctx =
    Maybe.withDefault
        Unsupported
        (tryAlternative
            (checkLiteralsWithDefault cases
                |> Maybe.map (\(literalCases, defaultResult) -> LiteralsWithDefault literalCases defaultResult))
            (\_ -> checkUnionWithNoParamsWithDefault value cases ctx))
