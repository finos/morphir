module Morphir.Snowpark.PatternMatchMapping exposing (mapPatternMatch, PatternMatchValues)

{-| Generation for `PatternMatch` expressions
   
-}

import Dict
import Morphir.IR.Value exposing (Value, Pattern(..))
import Morphir.Scala.AST as Scala
import Morphir.IR.Literal exposing (Literal)
import Morphir.IR.Value as Value exposing (TypedValue)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Name as Name
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.Constants as Constants exposing (applySnowparkFunc, ValueGenerationResult)
import Morphir.Snowpark.MappingContext exposing (
          ValueMappingContext
          , addReplacementForIdentifier
          , isUnionTypeRefWithoutParams
          , isUnionTypeRefWithParams )
import Morphir.Snowpark.Utils exposing (tryAlternatives, collectMaybeList)
import Morphir.Snowpark.ReferenceUtils exposing (mapLiteral
           , scalaReferenceToUnionTypeCase
           , getCustomTypeParameterFieldAccess)
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue)
import Morphir.Snowpark.ReferenceUtils exposing (simplifyBooleanExpression)


type alias PatternMatchValues = (Type (), TypedValue, List ( Pattern (Type ()), TypedValue ))

equalExpr : Scala.Value -> Scala.Value -> Scala.Value
equalExpr left right = Scala.BinOp left "===" right

createChainOfWhenCalls : (Scala.Value, Scala.Value) -> List (Scala.Value, Scala.Value) -> Scala.Value
createChainOfWhenCalls (firstCondition, firstValue) restConditionActionPairs =
    List.foldl
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

createChainOfWhenWithOptionalOtherwise : (Scala.Value, Scala.Value) -> List (Scala.Value, Scala.Value) -> Maybe Scala.Value -> Scala.Value
createChainOfWhenWithOptionalOtherwise first restConditionActionPairs maybeDefaultValue =
    case maybeDefaultValue of
        Just defaultValue ->
            createChainOfWhenWithOtherwise first restConditionActionPairs defaultValue
        _ ->
            createChainOfWhenCalls first restConditionActionPairs

mapPatternMatch :  PatternMatchValues  -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapPatternMatch (tpe, expr, cases) mapValue ctx =
    let
        (mappedTopExpr, topExprIssues) =
            mapValue expr ctx
    in
    case classifyScenario expr cases ctx of
        LiteralsWithDefault ((firstLit, firstExpr)::rest) defaultValue ->
            let
                compareWithExpr =  equalExpr mappedTopExpr
                litExpr = mapLiteral () firstLit
                (restPairs, restIssues) = 
                            rest
                              |> List.map (\(lit, val) -> (lit, (mapValue val ctx)))
                              |> List.map (\(lit, (mappedVal, issues)) -> ((compareWithExpr (mapLiteral () lit), mappedVal), issues))
                              |> List.unzip
                (mappedDefaultValue, defaultValueIssues) =
                    mapValue defaultValue ctx
                (mappedFirstExpr, firstExprIssues) =
                    mapValue firstExpr ctx
            in
            (createChainOfWhenWithOtherwise ((compareWithExpr litExpr), mappedFirstExpr) restPairs mappedDefaultValue
            , topExprIssues ++ (List.concat restIssues) ++ defaultValueIssues ++ firstExprIssues)

        UnionTypesWithoutParams ((firstConstr, firstExpr)::rest) maybeDefaultValue ->
            let
                compareWithExpr =  equalExpr mappedTopExpr
                
                (restPairs, restIssues) = 
                        rest 
                            |> List.map (\(lit, val) -> (lit, (mapValue val ctx)))
                            |> List.map (\(constr, (val, issues)) -> ((compareWithExpr constr, val), issues))
                            |> List.unzip
                (mappedFirstExpr, firstExprIssues) =
                    mapValue firstExpr ctx
                (mappedDefaultMaybe, defaultMaybeIssues) = 
                    mapMaybeValue maybeDefaultValue ctx mapValue
            in
            ( createChainOfWhenWithOptionalOtherwise (compareWithExpr firstConstr, mappedFirstExpr) restPairs mappedDefaultMaybe
            , topExprIssues ++ (List.concat restIssues) ++ defaultMaybeIssues ++ firstExprIssues)
        UnionTypesWithParams ((firstConstr, firstNestedPatternInfo, firstExpr)::rest) maybeDefaultValue ->
            let
                compareWithExpr : Name.Name -> Scala.Value
                compareWithExpr = \name -> 
                                   equalExpr (Scala.Apply mappedTopExpr [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "__tag"))])
                                             (applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit (Name.toTitleCase name))])
                (restPairs, restIssues) = 
                    rest 
                        |> List.map (\(constr, nestedPatternsInfos, val) -> 
                                            ( constr 
                                            , nestedPatternsInfos
                                            , (mapValue val (addBindingReplacementsToContext ctx nestedPatternsInfos mappedTopExpr))))
                        |> List.map (\(constr, nestedPatternsInfos, (val, issues)) -> (( generateNestedPatternsCondition nestedPatternsInfos mappedTopExpr (compareWithExpr constr), val), issues))
                        |> List.unzip
                (mappedDefaultMaybe, defaultMaybeIssues) = 
                    mapMaybeValue maybeDefaultValue ctx mapValue
                (mappedFirstExpr, firstExprIssues) =
                    mapValue firstExpr (addBindingReplacementsToContext ctx firstNestedPatternInfo mappedTopExpr)
                firstCondition =
                    generateNestedPatternsCondition firstNestedPatternInfo mappedTopExpr (compareWithExpr firstConstr)
            in
            ( createChainOfWhenWithOptionalOtherwise (firstCondition, mappedFirstExpr) restPairs mappedDefaultMaybe
            , defaultMaybeIssues ++ topExprIssues ++ (List.concat restIssues) ++ firstExprIssues)
        MaybeCase (justVariable, justExpr) nothingExpr ->
            let
                (generatedJustExpr, justIssues) = 
                    mapValue justExpr (Maybe.withDefault ctx (Maybe.map (\varName ->  { ctx | inlinedIds = Dict.insert varName mappedTopExpr ctx.inlinedIds }) justVariable))
                (generatedNothingExpr, nothingIssues) = mapValue nothingExpr ctx
            in
            ( createChainOfWhenWithOtherwise ((Scala.Select mappedTopExpr "is_not_null"), generatedJustExpr) [] generatedNothingExpr 
            , justIssues ++ nothingIssues)
        TupleCases (first::tupleCases) maybeDefaultValue ->
            let 
                (tupleCasesValues, valuesIssues) =
                    createTupleMatchingValues expr mapValue ctx
                (casesPairs, tupleissues) =
                    List.map (\tupleCase -> createCaseCodeForTuplePattern tupleCase tupleCasesValues mapValue ctx) tupleCases
                    |> List.unzip
                (mappedDefaultMaybe, defaultMaybeIssues) = 
                    mapMaybeValue maybeDefaultValue ctx mapValue
                (firstCase, firstCaseIssues) =
                    createCaseCodeForTuplePattern first tupleCasesValues mapValue ctx
            in
            ( createChainOfWhenWithOptionalOtherwise firstCase casesPairs mappedDefaultMaybe
            , defaultMaybeIssues ++ (List.concat valuesIssues) ++ firstCaseIssues ++ (List.concat tupleissues))
        _ ->
            (Scala.Variable "NOT_CONVERTED", ["`Case/of` expression not generated"])

mapMaybeValue : Maybe TypedValue -> ValueMappingContext -> Constants.MapValueType ->  (Maybe Scala.Value, List GenerationIssue)
mapMaybeValue maybeValue ctx mapValue =
    let
        mappedDefaultMaybeResult =
            maybeValue
                |> Maybe.map (\defaultValue -> mapValue defaultValue ctx)
        mappedDefaultMaybe = 
            mappedDefaultMaybeResult
                |> Maybe.map Tuple.first
        defaultMaybeIssues =
            mappedDefaultMaybeResult 
                |> Maybe.map Tuple.second
                |> Maybe.withDefault []
    in
    (mappedDefaultMaybe, defaultMaybeIssues)

createCaseCodeForTuplePattern : (List TuplePatternResult, Value () (Type ())) -> 
                                List Scala.Value -> 
                                Constants.MapValueType -> 
                                ValueMappingContext -> 
                                ((Scala.Value, Scala.Value), List GenerationIssue)
createCaseCodeForTuplePattern (tuplePats, value) positionValues mapValue ctx =
    let
        tuplesForConversion = List.map2 (\x y -> (x, y)) tuplePats positionValues
        mappingsContextWithReplacements = 
            tuplesForConversion
                |> List.foldl (\((TuplePatternResult funcs), val) currCtx -> funcs.contextManipulation val currCtx) ctx 
        condition = 
            tuplesForConversion 
              |>  List.foldr (\((TuplePatternResult funcs), val) currentCondition -> 
                                Scala.BinOp (funcs.conditionGenerator val) "&&" currentCondition ) 
                            (Scala.Literal (Scala.BooleanLit True)) 
              |> simplifyBooleanExpression
        (mappedSuccessValue, successValueIssues) = mapValue value mappingsContextWithReplacements
    in
    ((condition, mappedSuccessValue), successValueIssues)

createTupleMatchingValues : Value () (Type ()) -> Constants.MapValueType -> ValueMappingContext -> (List Scala.Value, List (List GenerationIssue))
createTupleMatchingValues expr mapValue ctx =
   case expr of
       Value.Tuple _ elements -> 
           elements 
                |> List.map (\e -> mapValue e ctx)
                |> List.unzip
       _ -> 
          let
              (convertedTuple, tupleIssues) = mapValue expr ctx
          in
          List.range 0 10
              |> List.map (\i -> (Scala.Apply convertedTuple [Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit i))], tupleIssues)) 
              |> List.unzip

generateBindingVariableExpr : String -> Scala.Value -> Scala.Value
generateBindingVariableExpr name expr =
    Scala.Apply expr [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit name))]


addBindingReplacementsToContext : ValueMappingContext -> List TuplePatternResult -> Scala.Value -> ValueMappingContext
addBindingReplacementsToContext ctxt nestedPatternsInfo referenceExpr =
    let 
        newContext = 
            nestedPatternsInfo
                |> List.indexedMap (\i nestedPatternInfo -> (nestedPatternInfo, generateBindingVariableExpr (getCustomTypeParameterFieldAccess i) referenceExpr))
                |> List.foldl (\(TuplePatternResult nestedPatternInfo, expr) newCtxt -> nestedPatternInfo.contextManipulation expr newCtxt) ctxt
    in
    newContext
generateNestedPatternsCondition : List TuplePatternResult -> Scala.Value -> Scala.Value -> Scala.Value
generateNestedPatternsCondition nestedPatternsInfo referenceExpr tagCondition =
    nestedPatternsInfo
        |> List.indexedMap (\i nestedPatternInfo -> (nestedPatternInfo, generateBindingVariableExpr (getCustomTypeParameterFieldAccess i) referenceExpr))
        |> List.foldl (\(TuplePatternResult nestedPatternInfo, expr) currentExpr -> 
                                (Scala.BinOp currentExpr "&&" (nestedPatternInfo.conditionGenerator expr))) tagCondition
        |> simplifyBooleanExpression

type PatternMatchScenario ta
    = LiteralsWithDefault (List (Literal, TypedValue)) (TypedValue)
    | UnionTypesWithoutParams (List (Scala.Value, TypedValue)) (Maybe (TypedValue))
    | UnionTypesWithParams (List (Name.Name, List TuplePatternResult, TypedValue)) (Maybe (TypedValue))    
    -- Right now we just support `Just` with variables
    | MaybeCase (Maybe Name.Name, TypedValue) (TypedValue)
    | TupleCases (List (List TuplePatternResult, TypedValue)) (Maybe (TypedValue))
    | Unsupported

checkForLiteralCase : ( Pattern (Type ()), TypedValue ) -> Maybe (Literal, TypedValue)
checkForLiteralCase (pattern, caseValue) = 
   case pattern of
        (LiteralPattern _ literal) -> 
            Just (literal, caseValue)
        _ -> 
            Nothing

checkLiteralsWithDefault : List ( Pattern (Type ()), TypedValue ) -> (Maybe ((List (Literal, TypedValue)), (TypedValue)))
checkLiteralsWithDefault cases =
   case List.reverse cases of
        ((WildcardPattern _, wildCardResult)::restReversed) -> 
            (collectMaybeList checkForLiteralCase restReversed) |> Maybe.map (\p -> (List.reverse p, wildCardResult))
        _ -> 
            Nothing

checkForUnionOfWithNoParams : ( Pattern (Type ()), TypedValue ) -> Maybe (Scala.Value, TypedValue)
checkForUnionOfWithNoParams (pattern, caseValue) = 
   case pattern of
        (ConstructorPattern (Type.Reference _ typeName _) name []) -> 
            Just (scalaReferenceToUnionTypeCase typeName name, caseValue)
        _ -> 
            Nothing

checkConstructorForUnionOfWithParams : ( Pattern (Type ()), TypedValue ) -> Maybe (Name.Name, List TuplePatternResult, TypedValue)
checkConstructorForUnionOfWithParams (pattern, caseValue) = 
   case pattern of
        (ConstructorPattern _  name patternArgs) -> 
            collectMaybeList checkTuplePatternItemPattern patternArgs
               |> Maybe.map (\patInfo -> (FQName.getLocalName name, patInfo, caseValue))
        _ -> 
            Nothing

checkUnionWithNoParamsWithDefault : TypedValue -> List ( Pattern (Type ()), TypedValue ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
checkUnionWithNoParamsWithDefault expr cases ctx =
    if isUnionTypeRefWithoutParams (Value.valueAttribute expr) ctx.typesContextInfo  then
        case List.reverse cases of
            ((WildcardPattern _, wildCardResult)::restReversed) -> 
                (collectMaybeList checkForUnionOfWithNoParams restReversed) 
                     |> Maybe.map List.reverse
                     |> Maybe.map (\p -> (UnionTypesWithoutParams p (Just wildCardResult)))
            ((ConstructorPattern _ _ [], _)::_) as constructorCases ->
                (collectMaybeList checkForUnionOfWithNoParams constructorCases) 
                     |> Maybe.map List.reverse
                     |> Maybe.map (\p -> (UnionTypesWithoutParams p Nothing))
            _ -> 
                Nothing
    else 
        Nothing

checkUnionWithParams : TypedValue -> List ( Pattern (Type ()), TypedValue ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
checkUnionWithParams expr cases ctx =
    if isUnionTypeRefWithParams (Value.valueAttribute expr) ctx.typesContextInfo  then
        case List.reverse cases of
            ((WildcardPattern _, wildCardResult)::restReversed) -> 
                (collectMaybeList checkConstructorForUnionOfWithParams restReversed) 
                     |> Maybe.map List.reverse
                     |> Maybe.map (\parts -> (UnionTypesWithParams parts (Just wildCardResult)))
            ((ConstructorPattern _ _ _, _)::_) as constructorCases ->
                (collectMaybeList checkConstructorForUnionOfWithParams constructorCases) 
                     |> Maybe.map List.reverse
                     |> Maybe.map (\parts -> (UnionTypesWithParams parts Nothing))
            _ -> 
                Nothing
    else 
        Nothing

checkMaybePattern : TypedValue -> List ( Pattern (Type ()), TypedValue ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
checkMaybePattern expr cases ctx =
    case (Value.valueAttribute expr) of
        Type.Reference _ ([["morphir"],["s","d","k"]],[["maybe"]],["maybe"]) _ ->
            case cases of
                [(ConstructorPattern  _ _ [ AsPattern _ (WildcardPattern _) varName], justExpr),
                 (WildcardPattern _, wildCardResult)] -> 
                    Just <| MaybeCase (Just varName, justExpr) wildCardResult
                [(ConstructorPattern  _ _ [], nothingExpr),
                 (WildcardPattern _, wildCardResult)] -> 
                    Just <| MaybeCase (Nothing, wildCardResult) nothingExpr
                [(ConstructorPattern  _ _ [ AsPattern _ (WildcardPattern _) varName], justExpr),
                 (ConstructorPattern  _ _ [], nothingExpr)] -> 
                    Just <| MaybeCase (Just varName, justExpr) nothingExpr
                [(ConstructorPattern  _ _ [], nothingExpr),
                 (ConstructorPattern  _ _ [ AsPattern _ (WildcardPattern _) varName], justExpr)] -> 
                    Just <| MaybeCase (Just varName, justExpr) nothingExpr
                _ -> Nothing
        _ -> Nothing

checkForTuplePatternCase : ( Pattern (Type ()), TypedValue ) -> Maybe (List TuplePatternResult, TypedValue)
checkForTuplePatternCase (pattern, caseValue) = 
   case pattern of
        (TuplePattern _ options) -> 
             (options 
                  |> collectMaybeList checkTuplePatternItemPattern)
                |> Maybe.map (\lst -> (lst, caseValue))
        _ -> 
            Nothing

type TuplePatternResult =
     TuplePatternResult { conditionGenerator: Scala.Value -> Scala.Value
                        , contextManipulation: Scala.Value -> ValueMappingContext -> ValueMappingContext } 

checkTuplePatternItemPattern : Pattern (Type ()) -> Maybe TuplePatternResult
checkTuplePatternItemPattern  pattern =
    case pattern of 
        WildcardPattern _  ->
            Just <| TuplePatternResult { conditionGenerator = (\_ -> Scala.Literal (Scala.BooleanLit True))
                                       , contextManipulation = (\_ ctx -> ctx) }
        AsPattern _ (WildcardPattern _) name ->
            Just <| TuplePatternResult { conditionGenerator = (\_ -> Scala.Literal (Scala.BooleanLit True))
                                       , contextManipulation = addReplacementForIdentifier name } 
        Value.ConstructorPattern _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) [ innerPattern ] ->
            (checkTuplePatternItemPattern innerPattern)
            |> Maybe.map (\(TuplePatternResult patObject) ->
                                (TuplePatternResult { conditionGenerator = \refr -> Scala.BinOp (Scala.Select refr "is_not_null") "&&" (patObject.conditionGenerator refr)
                                                    , contextManipulation =  patObject.contextManipulation }))
        Value.LiteralPattern _ literal ->
            Just <| TuplePatternResult { conditionGenerator = (\e -> Scala.BinOp e "===" (mapLiteral () literal))
                                       , contextManipulation = (\_ ctx -> ctx) }
        _ -> 
           Nothing

checkTuplePattern : List ( Pattern (Type ()), TypedValue ) -> (Maybe (PatternMatchScenario ta))
checkTuplePattern cases =
    case List.reverse cases of
        ((WildcardPattern _, wildCardResult)::restReversed) -> 
            (collectMaybeList checkForTuplePatternCase restReversed) 
                    |> Maybe.map List.reverse
                    |> Maybe.map (\casesToProcess -> (TupleCases casesToProcess (Just wildCardResult)))
        ((TuplePattern _ _, _)::_) as constructorCases ->
            (collectMaybeList checkForTuplePatternCase constructorCases) 
                    |> Maybe.map List.reverse
                    |> Maybe.map (\casesToProcess -> (TupleCases casesToProcess Nothing))
        _ -> 
            Nothing

classifyScenario : (TypedValue) -> List (Pattern (Type ()), TypedValue) -> ValueMappingContext -> PatternMatchScenario ta
classifyScenario value cases ctx =
    Maybe.withDefault
        Unsupported        
        (tryAlternatives
        [ (\_ -> 
              (checkLiteralsWithDefault cases
                 |> Maybe.map (\(literalCases, defaultResult) -> LiteralsWithDefault literalCases defaultResult)))
        , (\_ -> checkUnionWithNoParamsWithDefault value cases ctx)
        , (\_ -> checkUnionWithParams value cases ctx)
        , (\_ -> checkMaybePattern value cases ctx)
        , (\_ -> checkTuplePattern cases) ])
