module Morphir.Snowpark.JoinMapping exposing (..)

import Dict
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as ValueIR
import Morphir.Snowpark.Constants as Constants
import Morphir.IR.Type as TypeIR
import Morphir.IR.Name as Name
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)

processJoinProjection : ValueIR.Value ta (TypeIR.Type ()) -> Constants.MapValueType ta -> ValueMappingContext -> List Scala.Value
processJoinProjection projection mapValue ctx =
    case projection of
        ValueIR.Lambda _ _ (ValueIR.Record _ record) ->
            let
                listFields = Dict.toList record
                variables =  listFields |> List.map (\(_, x) -> mapValue x ctx) |> List.map (\x -> Scala.Select x "alias")
                alias = listFields |> List.map(\(x, _) ->  Scala.Literal (Scala.StringLit (Name.toCamelCase x)) )

                selectColumns = List.map2 (\name variable -> Scala.Apply variable [Scala.ArgValue Nothing name]) alias variables
            in
            selectColumns
        _ ->
            [Scala.Literal <| Scala.StringLit "Proyection"]

processJoinBody :  (ValueIR.Value ta (TypeIR.Type ())) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
processJoinBody joinValue mapValue ctx =
    case joinValue of
        ValueIR.Apply _ 
            (ValueIR.Apply 
                _ 
                (ValueIR.Apply _ ( ValueIR.Reference _  ([["morphir"],["s","d","k"]],[["list"]], joinName)) (ValueIR.Variable _ arg2))
                -- _
                (ValueIR.Lambda 
                    _ 
                    (ValueIR.AsPattern _ _ lambdaArg1Name)
                    (ValueIR.Lambda
                        _
                        (ValueIR.AsPattern _ _ lambdaArg2Name)
                        lambdaBody
                    )
                )
            ) 
            (ValueIR.Variable _ arg1) ->
                let
                    lambdaBodyScala = processJoinFunctionBody lambdaBody mapValue ctx
                    joinTypeName = getJoinType joinName
                in
                Scala.Apply 
                    (Scala.Select (Scala.Variable (Name.toCamelCase arg1)) "join")
                    [ Scala.ArgValue Nothing (Scala.Variable (Name.toCamelCase arg2))
                    , Scala.ArgValue Nothing lambdaBodyScala
                    , Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit joinTypeName))
                    ]
        _ ->
            Scala.Literal (Scala.StringLit "'Join' scenario not supported")

processJoinFunctionBody : ValueIR.Value ta (TypeIR.Type ()) -> Constants.MapValueType ta -> ValueMappingContext  -> Scala.Value
processJoinFunctionBody value mapValue ctx =
    case value of
        ValueIR.Apply _ x y ->
            mapValue value ctx
        _ ->
            Scala.Literal (Scala.StringLit "Join Body EXCEPTION")


getJoinVariable : ValueIR.Value ta (TypeIR.Type()) -> Scala.Value
getJoinVariable value =
    case value of
        ValueIR.Field tpe val name ->
            Scala.Literal (Scala.StringLit (Name.toCamelCase name))
        _ ->
            Scala.Literal (Scala.StringLit "")


getJoinType : Name.Name -> String
getJoinType name =
    if List.member "inner" name then
        "inner"
    else
        if List.member "inner" name then
            "right"
        else
            if List.member "inner" name then
                "left"
            else
                "Unsupported join Type"
