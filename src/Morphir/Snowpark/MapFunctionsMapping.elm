module Morphir.Snowpark.MapFunctionsMapping exposing (mapFunctionsMapping)

import Dict as Dict
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as ValueIR exposing (Pattern(..), Value(..))
import Morphir.IR.Type exposing (Type)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext, isCandidateForDataFrame)
import Morphir.IR.Value exposing (valueAttribute)
import Morphir.IR.Type as TypeIR
import Morphir.Snowpark.MappingContext exposing (isAnonymousRecordWithSimpleTypes)
import Morphir.IR.Name as Name
import Morphir.Snowpark.Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.MappingContext exposing (isBasicType)
import Morphir.Snowpark.Operatorsmaps exposing (mapOperator)

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
        ValueIR.Apply 
            (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]], _) [])
            (ValueIR.Apply 
                (TypeIR.Function 
                    () 
                    (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]], _ ) [])
                    (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]], _ ) [])
                )
                (ValueIR.Reference
                    (TypeIR.Function
                        () 
                        (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]], _ ) [])
                        (TypeIR.Function 
                            () 
                            (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]], _ ) []) 
                            (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]], _ ) []))
                    )
                    ([["morphir"],["s","d","k"]],[["basics"]], optname)
                )
                left )
            right ->
            let
                leftValue = mapValue left ctx
                rightValue = mapValue right ctx
                operatorname = mapOperator optname
            in
            Scala.BinOp leftValue operatorname rightValue
        ValueIR.Apply 
            (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["bool"]) [])
            (ValueIR.Apply (TypeIR.Function 
                        ()
                        (TypeIR.Variable () ["t","0"])
                        (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["bool"]) [])
                    )
                    (ValueIR.Reference (TypeIR.Function 
                                            ()
                                            (TypeIR.Variable () ["t","0"])
                                            (TypeIR.Function 
                                                ()
                                                (TypeIR.Variable () ["t","0"])
                                                (TypeIR.Reference () ([["morphir"],["s","d","k"]],[["basics"]],["bool"]) [])
                                            )
                                        )
                                ([["morphir"],["s","d","k"]],[["basics"]], optname)
                    )
                    left
            )
            right ->
            let
                leftValue = mapValue left ctx
                rightValue = mapValue right ctx
                operatorname = mapOperator optname
            in
            Scala.BinOp leftValue operatorname rightValue
        _ ->
            Scala.Literal (Scala.StringLit "To Do")


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
                            sumCall = applySnowparkFunc "sum" [applySnowparkFunc "col" [resultName]]
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
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case predicate of
           ValueIR.Lambda _ _ binExpr ->
              Scala.Apply (Scala.Select (mapValue sourceRelation ctx) "filter") [Scala.ArgValue Nothing <| mapValue binExpr ctx]
           _ ->
              Scala.Literal (Scala.StringLit "To Do")
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
                  isNotNullCall = Scala.Select (applySnowparkFunc "col" [ resultId ]) "is_not_null"
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
              Scala.Literal (Scala.StringLit "Unsupported map scenario")
     else 
        Scala.Literal (Scala.StringLit "Unsupported map scenario")

processLambdaWithRecordBody : Value ta (Type ()) -> ValueMappingContext -> MapValueType ta -> Maybe (List Scala.ArgValue)
processLambdaWithRecordBody functionExpr ctx mapValue =
    case functionExpr of
        ValueIR.Lambda (TypeIR.Function _ _  returnType) (ValueIR.AsPattern _ _ _) (ValueIR.Record _ fields) ->
             if isAnonymousRecordWithSimpleTypes returnType ctx.typesContextInfo then
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
        _ ->
            Nothing