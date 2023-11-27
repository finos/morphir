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

        UnionTypesWithoutParams ((firstConstr, firstExpr)::rest) (Just defaultValue) ->
            let
                compareWithExpr =  equalExpr mappedTopExpr
                
                (restPairs, restIssues) = 
                        rest 
                            |> List.map (\(lit, val) -> (lit, (mapValue val ctx)))
                            |> List.map (\(constr, (val, issues)) -> ((compareWithExpr constr, val), issues))
                            |> List.unzip
                (mappedDefaultValue, defaultValueIssues) =
                    mapValue defaultValue ctx
                (mappedFirstExpr, firstExprIssues) =
                    mapValue firstExpr ctx
            in
            ( createChainOfWhenWithOtherwise (compareWithExpr firstConstr, mappedFirstExpr) restPairs mappedDefaultValue
            , topExprIssues ++ (List.concat restIssues) ++ defaultValueIssues ++ firstExprIssues)
        UnionTypesWithoutParams ((firstConstr, firstExpr)::rest) Nothing ->
            let
                compareWithExpr =  equalExpr mappedTopExpr
                
                (restPairs, restIssues) = 
                        rest 
                            |> List.map (\(lit, val) -> (lit, (mapValue val ctx)))
                            |> List.map (\(constr, (val, issues)) -> ((compareWithExpr constr, val), issues))
                            |> List.unzip
                (mappedFirstExpr, firstExprIssues) =
                    mapValue firstExpr ctx
            in
            ( createChainOfWhenCalls (compareWithExpr firstConstr, mappedFirstExpr) restPairs
            , topExprIssues ++ (List.concat restIssues) ++ firstExprIssues)
        UnionTypesWithParams ((firstConstr, firstBindings, firstExpr)::rest) Nothing ->
            let
                compareWithExpr : Name.Name -> Scala.Value
                compareWithExpr = \name -> 
                                   equalExpr (Scala.Apply mappedTopExpr [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "__tag"))])
                                             (applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit (Name.toTitleCase name))])
                changeCtxt = 
                    addBindingReplacementsToContext ctx 
                (restPairs, restIssues) = 
                    rest 
                        |> List.map (\(constr, bindings, val) -> (constr, (mapValue val (changeCtxt bindings mappedTopExpr))))
                        |> List.map (\(constr, (val, issues)) -> (((compareWithExpr constr), val), issues))
                        |> List.unzip
                (mappedFirstExpr, firstExprIssues) =
                    mapValue firstExpr ctx
            in
            ( createChainOfWhenCalls (compareWithExpr firstConstr, mappedFirstExpr) restPairs
            , topExprIssues ++ (List.concat restIssues) ++ firstExprIssues)
        UnionTypesWithParams ((firstConstr, firstBindings, firstExpr)::rest) (Just defaultValue) ->
            let
               
                compareWithExpr = \name -> 
                                   equalExpr (Scala.Apply mappedTopExpr [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "__tag"))])
                                             (applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit ( Name.toTitleCase name))])
                changeCtxt = addBindingReplacementsToContext ctx 

                (restPairs, restIssues) = 
                    rest 
                        |> List.map (\(constr, bindings, val) -> (constr, (mapValue val (changeCtxt bindings mappedTopExpr))))
                        |> List.map (\(constr, (val, issues)) -> (((compareWithExpr constr), val), issues))
                        |> List.unzip

                (mappedDefaultValue, defaultValueIssues) =
                    mapValue defaultValue ctx

                (mappedFirstExpr, firstExprIssues) =
                    mapValue firstExpr (changeCtxt firstBindings mappedTopExpr)
            in
            ( createChainOfWhenWithOtherwise (compareWithExpr firstConstr, mappedFirstExpr) restPairs mappedDefaultValue
            , topExprIssues ++ (List.concat restIssues) ++ firstExprIssues ++ defaultValueIssues)
        MaybeCase (justVariable, justExpr) nothingExpr ->
            let
                (generatedJustExpr, justIssues) = 
                    mapValue justExpr (Maybe.withDefault ctx (Maybe.map (\varName ->  { ctx | inlinedIds = Dict.insert varName mappedTopExpr ctx.inlinedIds }) justVariable))
                (generatedNothingExpr, nothingIssues) = mapValue nothingExpr ctx
            in
            ( createChainOfWhenWithOtherwise ((Scala.Select mappedTopExpr "is_not_null"), generatedJustExpr) [] generatedNothingExpr 
            , justIssues ++ nothingIssues)
        TupleCases (first::tupleCases) (Just default) ->
            let 
                (tupleCasesValues, valuesIssues) =
                    createTupleMatchingValues expr mapValue ctx
                (casesPairs, tupleissues) =
                    List.map (\tupleCase -> createCaseCodeForTuplePattern tupleCase tupleCasesValues mapValue ctx) tupleCases
                    |> List.unzip
                    
                (mappedDefault, defaultIssues) =
                    mapValue default ctx
                (t, tupleIssues2) =
                        createCaseCodeForTuplePattern first tupleCasesValues mapValue ctx
            in
            ( createChainOfWhenWithOtherwise t casesPairs mappedDefault
            , defaultIssues ++ (List.concat valuesIssues) ++ tupleIssues2 ++ (List.concat tupleissues))
        _ ->
            (Scala.Variable "NOT_CONVERTED", ["Case/of expression not generated"])

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
          List.range 1 10
              |> List.map (\i -> (Scala.Apply convertedTuple [Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit i))], tupleIssues)) 
              |> List.unzip




generateBindingVariableExpr : String -> Scala.Value -> Scala.Value
generateBindingVariableExpr name expr =
    Scala.Apply expr [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit name))]

addBindingReplacementsToContext : ValueMappingContext -> List Name.Name -> Scala.Value -> ValueMappingContext
addBindingReplacementsToContext ctxt bindingVariables referenceExpr =
    let 
        newReplacements = 
            bindingVariables
                |> List.indexedMap (\i name -> (name, generateBindingVariableExpr (getCustomTypeParameterFieldAccess i) referenceExpr))
                |> Dict.fromList
    in
    { ctxt | inlinedIds  = Dict.union ctxt.inlinedIds newReplacements }

type PatternMatchScenario ta
    = LiteralsWithDefault (List (Literal, TypedValue)) (TypedValue)
    | UnionTypesWithoutParams (List (Scala.Value, TypedValue)) (Maybe (TypedValue))
    | UnionTypesWithParams (List (Name.Name, List Name.Name, TypedValue)) (Maybe (TypedValue))    
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

checkConstructorForUnionOfWithParams : ( Pattern (Type ()), TypedValue ) -> Maybe (Name.Name, List Name.Name, TypedValue)
checkConstructorForUnionOfWithParams (pattern, caseValue) = 
   let 
       identifyNameOnlyPattern : Pattern (Type ()) -> Maybe Name.Name
       identifyNameOnlyPattern =
           \p ->
               case p of
                   AsPattern _ (WildcardPattern _) name -> 
                        Just name
                   _ -> 
                        Nothing
   in
   case pattern of
        (ConstructorPattern _  name patternArgs) -> 
            collectMaybeList identifyNameOnlyPattern patternArgs
               |> Maybe.map (\names -> (name |> FQName.getLocalName, names, caseValue))
        _ -> 
            Nothing

checkUnionWithNoParamsWithDefault : TypedValue -> List ( Pattern (Type ()), TypedValue ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
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

checkUnionWithParams : TypedValue -> List ( Pattern (Type ()), TypedValue ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
checkUnionWithParams expr cases ctx =
    if isUnionTypeRefWithParams (Value.valueAttribute expr) ctx.typesContextInfo  then
        case List.reverse cases of
            ((WildcardPattern _, wildCardResult)::restReversed) -> 
                (collectMaybeList checkConstructorForUnionOfWithParams restReversed) 
                     |> Maybe.map (\parts -> (UnionTypesWithParams parts (Just wildCardResult)))
            ((ConstructorPattern _ _ [], _)::_) as constructorCases ->
                (collectMaybeList checkConstructorForUnionOfWithParams constructorCases) 
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
                        , contextManipulation: Scala.Value -> ValueMappingContext -> ValueMappingContext, tmp : Name.Name }

checkTuplePatternItemPattern : Pattern (Type ()) -> Maybe TuplePatternResult
checkTuplePatternItemPattern  pattern =
    case pattern of 
        AsPattern _ (WildcardPattern _) name ->
            Just <| TuplePatternResult { conditionGenerator = (\_ -> Scala.Literal (Scala.BooleanLit True))
                                       , contextManipulation = addReplacementForIdentifier name, tmp = name }
        Value.ConstructorPattern _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] ) [ AsPattern _ (WildcardPattern _) justName ] ->
            Just <|  TuplePatternResult { conditionGenerator = \refr -> Scala.Select refr "is_not_null"
                                        , contextManipulation =  addReplacementForIdentifier justName, tmp = justName }
        _ -> 
           Nothing

checkTuplePattern : TypedValue -> List ( Pattern (Type ()), TypedValue ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
checkTuplePattern expr cases ctx =
    case List.reverse cases of
        ((WildcardPattern _, wildCardResult)::restReversed) -> 
            (collectMaybeList checkForTuplePatternCase restReversed) 
                    |> Maybe.map (\p -> (TupleCases p (Just wildCardResult)))
        ((TuplePattern _ _, _)::_) as constructorCases ->
            (collectMaybeList checkForTuplePatternCase constructorCases) 
                    |> Maybe.map (\p -> (TupleCases p Nothing))
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
        , (\_ -> checkTuplePattern value cases ctx) ])
