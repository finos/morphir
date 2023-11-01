module Morphir.Snowpark.MapFunctionsMapping exposing (mapFunctionsMapping)

import Dict as Dict
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as ValueIR exposing (Pattern(..), Value(..))
import Morphir.IR.Type exposing (Type)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext, isCandidateForDataFrame)
import Morphir.IR.Value exposing (valueAttribute)
import Morphir.IR.Type as TypeIR
import Morphir.Snowpark.MappingContext exposing (isAnonymousRecordWithSimpleTypes
            , isLocalFunctionName)
import Morphir.IR.Name as Name
import Morphir.Snowpark.Constants as Constants
import Morphir.Snowpark.MappingContext exposing (isBasicType)
import Morphir.Snowpark.Operatorsmaps exposing (mapOperator)
import Morphir.Snowpark.ReferenceUtils exposing (scalaPathToModule)
import Morphir.Visual.BoolOperatorTree exposing (functionName)
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.MappingContext exposing (isTypeRefToRecordWithSimpleTypes)
import Morphir.Snowpark.TypeRefMapping exposing (generateRecordTypeWrapperExpression)

type alias MapValueType ta = ValueIR.Value ta (TypeIR.Type ()) -> ValueMappingContext -> Scala.Value

mapFunctionsMapping : ValueIR.Value ta (TypeIR.Type ()) -> MapValueType ta -> ValueMappingContext -> Scala.Value
mapFunctionsMapping value mapValue ctx =
    
    case value of
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "member" ] )) predicate) sourceRelation ->
            let
                variable = mapValue predicate ctx
                applySequence = mapValue sourceRelation ctx
            in
            Scala.Apply (Scala.Select variable "in") [ Scala.ArgValue Nothing applySequence ]
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "map" ] )) projection) sourceRelation ->
            generateForListMap projection sourceRelation ctx mapValue
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "filter" ] )) predicate) sourceRelation ->
            generateForListFilter predicate sourceRelation ctx mapValue
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "filter", "map" ] )) predicateAction) sourceRelation ->
            generateForListFilterMap predicateAction sourceRelation ctx mapValue
        ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "sum" ] )) collection ->
            generateForListSum collection ctx mapValue
        ValueIR.Apply _ (ValueIR.Constructor _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "just" ] )) justValue ->
            mapValue justValue ctx 
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "with", "default" ] )) default) maybeValue ->
            mapWithDefaultCall default maybeValue mapValue ctx
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "map" ] )) action) maybeValue ->
            mapMaybeMapCall action maybeValue mapValue ctx
        ValueIR.Apply 
            (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]], _) [])
            (ValueIR.Apply 
                _
                (ValueIR.Reference
                    _
                    ([["morphir"],["s","d","k"]],[["basics"]], optname)
                )
                left )
            right ->
            mapForOperatorCall optname left right mapValue ctx

        ValueIR.Apply 
            (TypeIR.Reference 
                () 
                ([["morphir"],["s","d","k"]],[["basics"]],["bool"])
                []
            )
            (ValueIR.Reference
                (TypeIR.Function 
                    () 
                    (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["bool"]) [])
                    (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["bool"]) []))
                ([["morphir"],["s","d","k"]],[["basics"]],["not"])
            )
            variable ->
                let
                  assign = mapValue variable ctx
                in
                Scala.UnOp "!" assign
        ValueIR.Apply
            _
            (ValueIR.Reference
                _
                ([["morphir"],["s","d","k"]],[["basics"]],["floor"])
            )
            variable ->
            let
                number = mapValue variable ctx
            in
            Constants.applySnowparkFunc  "floor" [number]            
        ValueIR.Apply _ func arg -> 
            tryToConvertUserFunctionCall (ValueIR.uncurryApply func arg) mapValue ctx
        _ ->
            Scala.Literal (Scala.StringLit "To Do")


mapForOperatorCall : Name.Name -> Value ta (Type ()) -> Value ta (Type ()) -> MapValueType ta -> ValueMappingContext -> Scala.Value
mapForOperatorCall optname left right mapValue ctx =
    case (optname, left, right) of
        (["equal"], _ , ValueIR.Constructor _ ([ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ])) -> 
            Scala.Select (mapValue left ctx) "is_null"
        ([ "not", "equal" ], _ , ValueIR.Constructor _ ([ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ])) -> 
            Scala.Select (mapValue left ctx) "is_not_null"
        _ ->
            let
                leftValue = mapValue left ctx
                rightValue = mapValue right ctx
                operatorname = mapOperator optname
            in
            Scala.BinOp leftValue operatorname rightValue


tryToConvertUserFunctionCall : ((Value a (Type ())), List (Value a (Type ()))) -> MapValueType a -> ValueMappingContext -> Scala.Value
tryToConvertUserFunctionCall (func, args) mapValue ctx =
   case func of
       ValueIR.Reference _ functionName -> 
            if isLocalFunctionName functionName ctx then
                let 
                    funcReference = 
                        Scala.Ref (scalaPathToModule functionName) 
                                  (functionName |> FQName.getLocalName |> Name.toCamelCase)
                    argsToUse =
                        args 
                            |> List.map (\arg -> mapValue arg ctx)
                            |> List.map (Scala.ArgValue Nothing)
                in
                case argsToUse of
                    [] -> 
                        funcReference
                    (first::rest) -> 
                        List.foldr (\a c -> Scala.Apply c [a]) (Scala.Apply funcReference [first]) rest
            else
                Scala.Literal (Scala.StringLit "Call not converted")
       ValueIR.Constructor _ constructorName ->
            if isLocalFunctionName constructorName ctx && List.length args > 0 then
                let
                    argsToUse =
                         args 
                              |> List.indexedMap (\i arg -> ("field" ++ (String.fromInt i), mapValue arg ctx))
                              |> List.concatMap (\(field, value) -> [Constants.applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit field)], value])
                    tag = [ Constants.applySnowparkFunc "lit" [Scala.Literal (Scala.StringLit "__tag")],
                            Constants.applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit <| ( constructorName |> FQName.getLocalName |> Name.toTitleCase))]]
                in Constants.applySnowparkFunc "object_construct" (tag ++ argsToUse)
            else
                Scala.Literal (Scala.StringLit "Constructor call not converted")
       _ -> 
            Scala.Literal (Scala.StringLit "Call not converted")

whenConditionElseValueCall : Scala.Value -> Scala.Value -> Scala.Value -> Scala.Value
whenConditionElseValueCall condition thenExpr elseExpr =
   Scala.Apply (Scala.Select (Constants.applySnowparkFunc "when" [condition, thenExpr]) "otherwise") 
               [Scala.ArgValue Nothing elseExpr]


mapWithDefaultCall : Value ta (Type ()) -> Value ta (Type ()) -> (MapValueType ta) -> ValueMappingContext -> Scala.Value
mapWithDefaultCall default maybeValue mapValue ctx =
    Constants.applySnowparkFunc "coalesce" [mapValue maybeValue ctx, mapValue default ctx]

mapMaybeMapCall : Value ta (Type ()) -> Value ta (Type ()) -> (MapValueType ta) -> ValueMappingContext -> Scala.Value
mapMaybeMapCall action maybeValue mapValue ctx =
    case action of
        ValueIR.Lambda _ (AsPattern _ (WildcardPattern _) lambdaParam) body ->
            let
                convertedValue = mapValue maybeValue ctx
                newReplacements = Dict.fromList [(lambdaParam, convertedValue)]
                lambdaBody = mapValue body { ctx | inlinedIds  = Dict.union ctx.inlinedIds newReplacements }
                elseLiteral = Constants.applySnowparkFunc "lit" [(Scala.Literal (Scala.NullLit))]
            in
            whenConditionElseValueCall (Scala.Select convertedValue "is_not_null") lambdaBody elseLiteral
        _ -> 
            Scala.Literal (Scala.StringLit "Unsupported withDefault call")


generateForListSum : Value ta (Type ()) -> ValueMappingContext -> MapValueType ta -> Scala.Value
generateForListSum collection ctx mapValue =
    case collection of
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "map" ] )) _) sourceRelation ->
            if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
                case mapValue collection ctx of
                    Scala.Apply col [Scala.ArgValue argName projectedExpr] ->
                        let
                            resultName = Scala.Literal (Scala.StringLit "result")
                            asCall =  Scala.Apply (Scala.Select projectedExpr "as") [Scala.ArgValue Nothing resultName]
                            newSelect = Scala.Apply col [Scala.ArgValue argName asCall]
                            sumCall = Constants.applySnowparkFunc "sum" [Constants.applySnowparkFunc "col" [resultName]]
                        in
                            Scala.Apply (Scala.Select newSelect "select") [Scala.ArgValue Nothing sumCall]
                    _ ->
                        Scala.Literal (Scala.StringLit "Unsupported sum scenario")
            else 
                Scala.Literal (Scala.StringLit "Unsupported sum scenario")
        _ -> 
            Scala.Literal (Scala.StringLit "Unsupported sum scenario")

generateForListFilter : Value ta (Type ()) -> (Value ta (Type ())) -> ValueMappingContext -> MapValueType ta -> Scala.Value
generateForListFilter predicate sourceRelation ctx mapValue =
    let
        generateFilterCall functionExpr =
             Scala.Apply 
                    (Scala.Select (mapValue sourceRelation ctx) "filter") 
                    [Scala.ArgValue Nothing functionExpr]
    in
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case predicate of
           ValueIR.Lambda _ _ bodyExpr ->
              generateFilterCall <| mapValue bodyExpr ctx
           ValueIR.Reference (TypeIR.Function _ fromType _) functionName ->
                case (isLocalFunctionName functionName ctx, generateRecordTypeWrapperExpression fromType ctx) of
                    (True, Just typeRefExpr) ->                        
                        (generateFilterCall <| 
                            Scala.Apply (Scala.Ref (scalaPathToModule functionName) (functionName |> FQName.getLocalName |> Name.toCamelCase)) 
                                        [Scala.ArgValue Nothing typeRefExpr])
                    _ -> 
                        Scala.Literal (Scala.StringLit ("Unsupported filter function scenario2" ))
           _ ->
              Scala.Literal (Scala.StringLit ("Unsupported filter function scenario" ))
     else 
        Scala.Literal (Scala.StringLit "Unsupported filter scenario")


generateForListFilterMap : Value ta (Type ()) -> (Value ta (Type ())) -> ValueMappingContext -> MapValueType ta -> Scala.Value
generateForListFilterMap predicate sourceRelation ctx mapValue =
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case predicate of
           ValueIR.Lambda _ _ binExpr ->
              let 
                  selectCall = Scala.Apply (Scala.Select (mapValue sourceRelation ctx) "select") [Scala.ArgValue Nothing <| mapValue binExpr ctx]
                  resultId = Scala.Literal <| Scala.StringLit "result"
                  selectColumnAlias = Scala.Apply (Scala.Select selectCall "as ") [ Scala.ArgValue Nothing resultId ]
                  isNotNullCall = Scala.Select (Constants.applySnowparkFunc "col" [ resultId ]) "is_not_null"
              in
              Scala.Apply (Scala.Select selectColumnAlias "filter") [Scala.ArgValue Nothing isNotNullCall]
           _ ->
              Scala.Literal (Scala.StringLit "Unsupported filterMap scenario")
     else 
        Scala.Literal (Scala.StringLit "Unsupported filterMap scenario")

generateForListMap : Value ta (Type ()) -> (Value ta (Type ())) -> ValueMappingContext -> MapValueType ta -> Scala.Value
generateForListMap projection sourceRelation ctx mapValue =
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case processLambdaWithRecordBody projection ctx mapValue of
           Just arguments -> 
              Scala.Apply (Scala.Select (mapValue sourceRelation ctx) "select") arguments
           Nothing ->
              Scala.Literal (Scala.StringLit "Unsupported map scenario 1")
     else 
        Scala.Literal (Scala.StringLit "Unsupported map scenario 2")

processLambdaWithRecordBody : Value ta (Type ()) -> ValueMappingContext -> MapValueType ta -> Maybe (List Scala.ArgValue)
processLambdaWithRecordBody functionExpr ctx mapValue =
    case functionExpr of
        ValueIR.Lambda (TypeIR.Function _ _  returnType) (ValueIR.AsPattern _ _ _) (ValueIR.Record _ fields) ->
             if isAnonymousRecordWithSimpleTypes returnType ctx.typesContextInfo
                || isTypeRefToRecordWithSimpleTypes returnType ctx.typesContextInfo  then
               Just (fields  
                        |> Dict.toList
                        |> List.map (\(fieldName, value) -> (Name.toCamelCase fieldName, (mapValue value ctx)))
                        |> List.map (\(fieldName, value) ->  Scala.Apply (Scala.Select value  "as") [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit fieldName))])
                        |> List.map (Scala.ArgValue Nothing))
             else  
                Nothing
        ValueIR.Lambda (TypeIR.Function _ _  returnType) (ValueIR.AsPattern _ _ _) expr ->
             if isBasicType returnType then
                Just [ Scala.ArgValue Nothing <| mapValue expr ctx ]
             else  
                Nothing
        ValueIR.FieldFunction _ _ ->
            Just [Scala.ArgValue Nothing (mapValue functionExpr ctx)]
        _ ->
            Nothing