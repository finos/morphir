module Morphir.Snowpark.PatternMatchMapping exposing (..)

{-| Generation for `PatternMatch` expressions
   
-}

import Dict exposing (Dict)
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (Value, Pattern(..))
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Scala.AST as Scala
import Morphir.IR.Literal exposing (Literal)
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.ReferenceUtils exposing (mapLiteral
           , scalaReferenceToUnionTypeCase)
import Morphir.IR.Value as Value
import Morphir.Snowpark.MappingContext exposing (isUnionTypeRefWithoutParams
          , isUnionTypeRefWithParams )
import Morphir.IR.Type as Type
import Morphir.IR.Name as Name
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.MappingContext exposing (isUnionTypeWithParams)

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
        UnionTypesWithParams ((firstConstr, firstBindings, firstExpr)::rest) Nothing ->
            let
                referenceExpr = mapValue expr ctx
                compareWithExpr : Name.Name -> Scala.Value
                compareWithExpr = \name -> 
                                   equalExpr (Scala.Apply referenceExpr [Scala.ArgValue Nothing (applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit "__tag")])])
                                             (applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit (Name.toTitleCase name))])
                changeCtxt = addBindingReplacementsToContext ctx 
                restPairs = rest |> List.map (\(constr, bindings, val) -> ((compareWithExpr constr), (mapValue val (changeCtxt bindings referenceExpr))))
            in
            createChainOfWhenCalls (compareWithExpr firstConstr, mapValue firstExpr ctx) restPairs
        UnionTypesWithParams ((firstConstr, firstBindings, firstExpr)::rest) (Just defaultValue) ->
            let
                referenceExpr = mapValue expr ctx
                compareWithExpr = \name -> 
                                   equalExpr (Scala.Apply (mapValue expr ctx) [Scala.ArgValue Nothing (applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit "__tag")])])
                                             (applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit ( Name.toTitleCase name))])
                changeCtxt = addBindingReplacementsToContext ctx 
                restPairs = rest |> List.map (\(constr, bindings, val) -> ((compareWithExpr constr), (mapValue val (changeCtxt bindings referenceExpr))))
            in
            createChainOfWhenWithOtherwise (compareWithExpr firstConstr, mapValue firstExpr (changeCtxt firstBindings referenceExpr)) restPairs (mapValue defaultValue ctx)
        MaybeCase (justVariable, justExpr) nothingExpr ->
            let
                referenceExpr = mapValue expr ctx
                generatedJustExpr = 
                    mapValue justExpr (Maybe.withDefault ctx (Maybe.map (\varName ->  { ctx | inlinedIds = Dict.insert varName referenceExpr ctx.inlinedIds }) justVariable))
                generatedNothingExpr = mapValue nothingExpr ctx
            in
            createChainOfWhenWithOtherwise ((Scala.Select referenceExpr "is_not_null"), generatedJustExpr) [] generatedNothingExpr
        _ ->
            Scala.Variable "NOT_CONVERTED"

generateBindingVariableExpr : Name.Name -> Scala.Value -> Scala.Value
generateBindingVariableExpr name expr =
    Scala.Apply expr [Scala.ArgValue Nothing (applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit (name |> Name.toCamelCase))])]

addBindingReplacementsToContext : ValueMappingContext -> List Name.Name -> Scala.Value -> ValueMappingContext
addBindingReplacementsToContext ctxt bindingVariables referenceExpr =
    let 
        newReplacements = 
            bindingVariables
                |> List.map (\name -> (name, generateBindingVariableExpr name referenceExpr))
                |> Dict.fromList
    in
    { ctxt | inlinedIds  = Dict.union ctxt.inlinedIds newReplacements }

type PatternMatchScenario ta
    = LiteralsWithDefault (List (Literal, Value ta (Type ()))) (Value ta (Type ()))
    | UnionTypesWithoutParams (List (Scala.Value, Value ta (Type ()))) (Maybe (Value ta (Type ())))
    | UnionTypesWithParams (List (Name.Name, List Name.Name, Value ta (Type ()))) (Maybe (Value ta (Type ())))
    -- Right now we just support `Just` with variables
    | MaybeCase (Maybe Name.Name, Value ta (Type ())) (Value ta (Type ()))
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

checkConstructorForUnionOfWithParams : ( Pattern (Type ()), Value ta (Type ()) ) -> Maybe (Name.Name, List Name.Name, Value ta (Type ()))
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


checkUnionWithParams : Value ta (Type ()) -> List ( Pattern (Type ()), Value ta (Type ()) ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
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

checkMaybePattern : Value ta (Type ()) -> List ( Pattern (Type ()), Value ta (Type ()) ) -> ValueMappingContext -> (Maybe (PatternMatchScenario ta))
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


tryAlternative :  (() -> Maybe a) -> Maybe a -> Maybe a
tryAlternative nextAction currentResult  =
    case currentResult of
        Nothing -> 
            nextAction ()
        _ -> 
            currentResult

tryAlternatives : List (() -> Maybe a) -> Maybe a
tryAlternatives cases =
   case cases of
       first::rest ->
            case first() of
                Just _ as result -> 
                    result
                _ ->
                    tryAlternatives rest
       [] -> 
            Nothing

classifyScenario : (Value ta (Type ())) -> List (Pattern (Type ()), Value ta (Type ())) -> ValueMappingContext -> PatternMatchScenario ta
classifyScenario value cases ctx =
    Maybe.withDefault
        Unsupported        
        (tryAlternatives
        [ (\_ -> 
              (checkLiteralsWithDefault cases
                 |> Maybe.map (\(literalCases, defaultResult) -> LiteralsWithDefault literalCases defaultResult)))
        , (\_ -> checkUnionWithNoParamsWithDefault value cases ctx)
        , (\_ -> checkUnionWithParams value cases ctx)
        , (\_ -> checkMaybePattern value cases ctx) ])
