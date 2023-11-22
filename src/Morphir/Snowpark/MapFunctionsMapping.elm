module Morphir.Snowpark.MapFunctionsMapping exposing (mapFunctionsMapping, dataFrameMappings, MappingFunctionType, FunctionMappingTable, IrValueType, listFunctionName, mapUncurriedFunctionCall,
                      basicsFunctionName)

import Dict as Dict exposing (Dict)
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as ValueIR exposing (Pattern(..), Value(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value exposing (valueAttribute)
import Morphir.IR.Type as TypeIR
import Morphir.IR.Name as Name
import Morphir.IR.FQName as FQName
import Morphir.IR.Value as Value
import Morphir.Snowpark.AggregateMapping as AggregateMapping
import Morphir.Snowpark.Constants as Constants exposing (applySnowparkFunc)
import Morphir.Snowpark.Operatorsmaps exposing (mapOperator)
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord
            , scalaPathToModule
            , getCustomTypeParameterFieldAccess)
import Morphir.Snowpark.TypeRefMapping exposing (generateRecordTypeWrapperExpression,  generateCastIfPossible)
import Morphir.Snowpark.MappingContext exposing (
            ValueMappingContext
            , isBasicType
            , isTypeRefToRecordWithSimpleTypes
            , isCandidateForDataFrame
            , isFunctionReturningDataFrameExpressions
            , isAnonymousRecordWithSimpleTypes
            , isLocalFunctionName
            , getFieldInfoIfRecordType
            , addReplacementForIdentifier
            , getLocalVariableIfDataFrameReference)
import Morphir.Snowpark.Utils exposing (collectMaybeList)
import Morphir.Snowpark.ReferenceUtils exposing (getListTypeParameter)
import Morphir.Snowpark.UserDefinedFunctionMapping exposing (tryToConvertUserFunctionCall)


type alias IrValueType ta = ValueIR.Value ta (TypeIR.Type ())

type alias MappingFunctionType ta = (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value

type alias FunctionMappingTable ta = Dict FQName.FQName (MappingFunctionType ta)

listFunctionName : Name.Name -> FQName.FQName
listFunctionName simpleName = 
    ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], simpleName )

maybeFunctionName : Name.Name -> FQName.FQName
maybeFunctionName simpleName = 
    ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], simpleName )

basicsFunctionName : Name.Name -> FQName.FQName
basicsFunctionName simpleName =
   ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], simpleName )

dataFrameMappings : FunctionMappingTable ta
dataFrameMappings =
    [ ( listFunctionName [ "member" ], mapListMemberFunction)
    , ( listFunctionName [ "map" ], mapListMapFunction )
    , ( listFunctionName [ "filter" ], mapListFilterFunction ) 
    , ( listFunctionName [ "filter", "map"], mapListFilterMapFunction ) 
    , ( listFunctionName [ "concat", "map"], mapListConcatMapFunction ) 
    , ( listFunctionName [ "concat" ], mapListConcatFunction ) 
    , ( listFunctionName [ "sum" ], mapListSumFunction ) 
    , ( maybeFunctionName [ "just" ], mapJustFunction )
    , ( maybeFunctionName [ "map" ], mapMaybeMapFunction )
    , ( maybeFunctionName [ "with", "default" ], mapMaybeWithDefaultFunction )
    , ( basicsFunctionName ["add"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["subtract"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["multiply"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["divide"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["integer", "divide"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["float", "divide"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["equal"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["not", "equal"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["greater", "than"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["less", "than"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["less", "than", "or", "equal"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["greater", "than", "or", "equal"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["and"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["or"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["mod", "by"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["sum", "of"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["average", "of"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["maximum", "of"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["minimum", "of"] , mapBasicsFunctionCall )
    , ( basicsFunctionName ["not"] , mapNotFunctionCall )
    , ( basicsFunctionName ["floor"] , mapFloorFunctionCall )
    , ( ([["morphir"], ["s","d","k"]], [["aggregate"]], ["aggregate"]), mapAggregateFunction )
    ]
        |> Dict.fromList

mapFunctionsMapping : ValueIR.Value () (TypeIR.Type ()) -> Constants.MapValueType () -> ValueMappingContext -> Scala.Value
mapFunctionsMapping value mapValue ctx =
    case value of
        ValueIR.Apply _ function arg ->
            mapUncurriedFunctionCall (Value.uncurryApply function arg) mapValue dataFrameMappings ctx
        _ ->
            Scala.Literal (Scala.StringLit "To Do")

getFullNameIfReferencedElement : IrValueType ta -> Maybe FQName.FQName
getFullNameIfReferencedElement value =
    case value of
        ValueIR.Reference _ fullName ->
            Just fullName
        ValueIR.Constructor _ fullName ->
            Just fullName
        _ ->
            Nothing

mapUncurriedFunctionCall : (IrValueType (), List (IrValueType ())) -> Constants.MapValueType () -> FunctionMappingTable () -> ValueMappingContext -> Scala.Value
mapUncurriedFunctionCall (func, args) mapValue mappings ctx =    
    let
        funcNameIfAvailable =
            getFullNameIfReferencedElement func
        inlineFunctionIfAvailable = 
            funcNameIfAvailable
                    |> Maybe.map (\fullName -> Dict.get fullName mappings)
                    |> Maybe.withDefault Nothing
        builtinMappingFunction =
            getFullNameIfReferencedElement func
                |> Maybe.map (getInliningFunctionIfRequired ctx)
                |> Maybe.withDefault Nothing
    in
    case (inlineFunctionIfAvailable, builtinMappingFunction) of
        (Just inliningFunction, _) ->
            inliningFunction (func, args) mapValue ctx
        (_, Just mappingFunc) ->
            mappingFunc (func, args) mapValue ctx
        _ -> 
            tryToConvertUserFunctionCall (func, args) mapValue ctx

getInliningFunctionIfRequired : ValueMappingContext -> FQName.FQName -> Maybe (MappingFunctionType ())
getInliningFunctionIfRequired ctx name =
   Dict.get name ctx.globalValuesToInline
      |> Maybe.map (\definition ->
            \(_, args) mapValue innerCtx ->
                let
                    convertedArgs = 
                        List.map2 (\arg (paramName, _, _) -> (paramName, mapValue arg ctx)) args definition.inputTypes
                            
                    newCtx = 
                        convertedArgs
                            |> List.foldr (\(paramName, value) currentCtx -> 
                                                addReplacementForIdentifier paramName value currentCtx) innerCtx 
                in
                mapValue definition.body newCtx)


mapListMemberFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListMemberFunction ( _, args ) mapValue ctx =
    case args of
        [ value, sourceRelation ] ->
            let
                variable = mapValue value ctx
                applySequence = mapValue sourceRelation ctx
            in
            Scala.Apply (Scala.Select variable "in") [ Scala.ArgValue Nothing applySequence ]
        _ ->
            Scala.Literal (Scala.StringLit "List.member scenario not converted")

mapListConcatMapFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListConcatMapFunction ( _, args ) mapValue ctx =
    case args of    
        [ filterAction, sourceRelation ] ->
            generateForConcatMap filterAction sourceRelation ctx mapValue
        _ ->
            Scala.Literal (Scala.StringLit "List concatMap scenario not supported")

generateForConcatMap : Value ta (Type ()) -> Value ta (Type ()) -> ValueMappingContext -> (Constants.MapValueType ta) -> Scala.Value
generateForConcatMap action sourceRelation ctx mapValue =
    case (action, Value.valueAttribute sourceRelation) of
        (Value.Lambda ((TypeIR.Function _ fromType toType) as lambdaFunctionType) (AsPattern _ _ lambdaParam) body, sourceRelationType) ->
            if isCandidateForDataFrame sourceRelationType ctx.typesContextInfo && 
               isCandidateForDataFrame toType ctx.typesContextInfo then
               let 
                    contextForBody = 
                        isTypeReferenceToSimpleTypesRecord fromType ctx.typesContextInfo
                            |> Maybe.map (\(path, name) -> addReplacementForIdentifier lambdaParam (Scala.Ref path (Name.toTitleCase name)) ctx)
                            |> Maybe.withDefault ctx
                    selectArg =
                        (Scala.Apply 
                               (Scala.Select (mapValue body contextForBody) "as") 
                               [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "result")) ])
                    flattenedDataFrame =
                        (Scala.Apply
                            (Scala.Select 
                                (Scala.Apply 
                                    (Scala.Select (mapValue sourceRelation ctx) "select") [Scala.ArgValue Nothing selectArg])
                                "flatten")
                            [Scala.ArgValue Nothing (applySnowparkFunc "col" [ Scala.Literal (Scala.StringLit "result") ])])
                    finalProjection = generateProjectionForArrayColumnIfRequired lambdaFunctionType ctx flattenedDataFrame "value"
                in
                Maybe.withDefault flattenedDataFrame finalProjection
            else
                Scala.Literal (Scala.StringLit "List.concatMap scenario not supported")
        _ ->
            Scala.Literal (Scala.StringLit "List.concatMap scenario not supported")

mapListConcatFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListConcatFunction ( _, args ) mapValue ctx =
    case args of    
        [ elements ] ->
            generateForListConcat elements ctx mapValue
        _ ->
            Scala.Literal (Scala.StringLit "List concat scenario not supported")

generateForListConcat : Value ta (Type ()) -> ValueMappingContext -> (Constants.MapValueType ta) -> Scala.Value
generateForListConcat expr ctx mapValue =
    case expr of
        ValueIR.List (TypeIR.Reference _ _ [TypeIR.Reference _ _ [innerType]]) elements ->
              if isTypeRefToRecordWithSimpleTypes innerType ctx.typesContextInfo &&
                  hasFunctionToDfOpertions elements ctx then
                let 
                    convertedItems = elements |> List.map (\item -> mapValue item ctx)
                in
                applySnowparkFunc "callBuiltin" ((Scala.Literal (Scala.StringLit "array_flatten")) :: [ applySnowparkFunc "array_construct" convertedItems])
               else 
                 generateUnionAllWithMappedElements elements ctx mapValue
        _ ->
            Scala.Literal (Scala.StringLit "List.concat case not supported")


generateUnionAllWithMappedElements : List (Value ta (Type ())) -> ValueMappingContext -> (Constants.MapValueType ta) -> Scala.Value
generateUnionAllWithMappedElements elements ctx mapValue =
    case elements of
        first::rest -> 
            let 
                firstMapped = 
                    mapValue first ctx
                in
                rest
                    |> List.foldl (\current result -> Scala.Apply (Scala.Select result "unionAll") [Scala.ArgValue Nothing (mapValue current ctx)] ) firstMapped
        _  ->
            Scala.Literal (Scala.StringLit "List.concat case not supported")

hasFunctionToDfOpertions : List (Value a (Type ())) -> ValueMappingContext -> Bool
hasFunctionToDfOpertions listElements ctx =
    case listElements of
        (((ValueIR.Apply _ f a ))::_) -> 
            case Value.uncurryApply f a of
                (ValueIR.Reference _ fullName , _) -> isFunctionReturningDataFrameExpressions fullName ctx
                _ -> 
                    False
        _ -> 
            False


mapBasicsFunctionCall : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapBasicsFunctionCall ( name, args ) mapValue ctx =
    case (name, args) of    
        (ValueIR.Reference _ fullFuncName, [ left, right ]) ->
            mapForOperatorCall (FQName.getLocalName fullFuncName) left right mapValue ctx
        _ ->
            Scala.Literal (Scala.StringLit "Basics function scenario not supported")


mapForOperatorCall : Name.Name -> Value ta (Type ()) -> Value ta (Type ()) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
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



whenConditionElseValueCall : Scala.Value -> Scala.Value -> Scala.Value -> Scala.Value
whenConditionElseValueCall condition thenExpr elseExpr =
   Scala.Apply (Scala.Select (Constants.applySnowparkFunc "when" [condition, thenExpr]) "otherwise") 
               [Scala.ArgValue Nothing elseExpr]


mapListSumFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListSumFunction ( _, args ) mapValue ctx =
    case args of    
        [ elements ] ->
            generateForListSum elements ctx mapValue
        _ ->
            Scala.Literal (Scala.StringLit "List sum scenario not supported")

generateForListSum : Value ta (Type ()) -> ValueMappingContext -> Constants.MapValueType ta -> Scala.Value
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
                            sumCall = Constants.applySnowparkFunc "coalesce" 
                                                                  [ Constants.applySnowparkFunc "sum" [Constants.applySnowparkFunc "col" [resultName]]
                                                                  , Constants.applySnowparkFunc "lit" [ Scala.Literal (Scala.IntegerLit 0)] ]
                            selectResult = Scala.Apply (Scala.Select newSelect "select") [Scala.ArgValue Nothing sumCall]
                        in
                            (Scala.Apply (Scala.Select (Scala.Select (Scala.Select selectResult "first") "get") "getDouble") [Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit 0))])
                            
                    _ ->
                        Scala.Literal (Scala.StringLit "Unsupported sum scenario")
            else 
                Scala.Literal (Scala.StringLit "Unsupported sum scenario")
        _ -> 
            Scala.Literal (Scala.StringLit "Unsupported sum scenario")


mapListFilterFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListFilterFunction ( _, args ) mapValue ctx =
    case args of    
        [ filter, sourceRelation ] ->
            generateForListFilter filter sourceRelation ctx mapValue
        _ ->
            Scala.Literal (Scala.StringLit "List filter scenario not supported")


generateForListFilter : Value ta (Type ()) -> (Value ta (Type ())) -> ValueMappingContext -> Constants.MapValueType ta -> Scala.Value
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


mapListFilterMapFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListFilterMapFunction ( _, args ) mapValue ctx =
    case args of    
        [ filter, sourceRelation ] ->
            generateForListFilterMap filter sourceRelation ctx mapValue
        _ ->
            Scala.Literal (Scala.StringLit "List filterMap scenario not supported")


generateForListFilterMap : Value ta (Type ()) -> (Value ta (Type ())) -> ValueMappingContext -> Constants.MapValueType ta -> Scala.Value
generateForListFilterMap predicate sourceRelation ctx mapValue =
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case predicate of
           ValueIR.Lambda tpe _ binExpr ->
              let 
                  selectColumnAlias = 
                       Scala.Apply (Scala.Select (mapValue binExpr ctx) "as ") [ Scala.ArgValue Nothing resultId ]
                  selectCall = 
                       Scala.Apply (Scala.Select (mapValue sourceRelation ctx) "select") [Scala.ArgValue Nothing <| selectColumnAlias]
                  resultId = 
                       Scala.Literal <| Scala.StringLit "result"
                  isNotNullCall = 
                       Scala.Select (Constants.applySnowparkFunc "col" [ resultId ]) "is_not_null"
                  filterCall = 
                       Scala.Apply (Scala.Select selectCall "filter") [Scala.ArgValue Nothing isNotNullCall]
              in
              Maybe.withDefault filterCall (generateProjectionForArrayColumnIfRequired  tpe ctx filterCall "result")
           _ ->
              let 
                  tpe = Value.valueAttribute predicate
                  recordReference =   getListTypeParameter (valueAttribute sourceRelation)
                                        |> Maybe.map (\t -> (getLocalVariableIfDataFrameReference t ctx))
                                        |> Maybe.withDefault Nothing
                                        |> Maybe.map Scala.Variable
                                        |> Maybe.withDefault (Scala.Literal Scala.NullLit)
                  predicateApplication = 
                    Scala.Apply (mapValue predicate ctx) [Scala.ArgValue Nothing recordReference]
                  selectColumnAlias = 
                       Scala.Apply (Scala.Select predicateApplication "as ") [ Scala.ArgValue Nothing resultId ]
                  selectCall = 
                       Scala.Apply (Scala.Select (mapValue sourceRelation ctx) "select") [Scala.ArgValue Nothing <| selectColumnAlias]
                  resultId = 
                       Scala.Literal <| Scala.StringLit "result"
                  isNotNullCall = 
                       Scala.Select (Constants.applySnowparkFunc "col" [ resultId ]) "is_not_null"
                  filterCall = 
                       Scala.Apply (Scala.Select selectCall "filter") [Scala.ArgValue Nothing isNotNullCall]
              in
              Maybe.withDefault filterCall (generateProjectionForArrayColumnIfRequired  tpe ctx filterCall "result")
     else 
        Scala.Literal (Scala.StringLit "Unsupported filterMap scenario")


generateProjectionForArrayColumnIfRequired : Type () -> ValueMappingContext -> Scala.Value -> String -> Maybe Scala.Value 
generateProjectionForArrayColumnIfRequired tpe ctx selectExpr resultColumnName =
    let
       resultColumn = 
            Constants.applySnowparkFunc "col" [Scala.Literal (Scala.StringLit resultColumnName)]
       generateFieldAccess : Int -> Scala.Value
       generateFieldAccess idx = 
            Scala.Literal (Scala.IntegerLit idx)
       generateAsCall expr name =
            Scala.Apply (Scala.Select expr "as") 
                        [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit (Name.toCamelCase name )))]
       resultFieldAccess idx = 
            Scala.Apply resultColumn [Scala.ArgValue Nothing <| generateFieldAccess idx] 
       generateArrayUnpackingProjection : List (Name.Name, Type ()) -> Scala.Value
       generateArrayUnpackingProjection names =
            Scala.Apply 
                    (Scala.Select selectExpr "select") 
                    (names 
                       |> List.indexedMap (\i (name, fType) -> Scala.ArgValue Nothing <| (generateAsCall (generateCastIfPossible ctx fType (resultFieldAccess i)) name)))
    in
    case tpe of
        TypeIR.Function _ _ (TypeIR.Reference _ _ [itemsType]) -> 
            (getFieldInfoIfRecordType itemsType ctx.typesContextInfo) 
                |> Maybe.map generateArrayUnpackingProjection
        _ -> Nothing  

generateProjectionForJsonColumnIfRequired : Type () -> ValueMappingContext -> Scala.Value -> String -> Maybe Scala.Value 
generateProjectionForJsonColumnIfRequired tpe ctx selectExpr resultColumnName =
    let
       resultColumn = 
            Constants.applySnowparkFunc "col" [Scala.Literal (Scala.StringLit resultColumnName)]
       generateFieldAccess : Int -> Scala.Value
       generateFieldAccess idx = 
            Scala.Literal (Scala.StringLit (getCustomTypeParameterFieldAccess idx))
       generateAsCall expr name =
            Scala.Apply (Scala.Select expr "as") 
                        [Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit (Name.toCamelCase name )))]
       resultFieldAccess idx = 
            Scala.Apply resultColumn [Scala.ArgValue Nothing <| generateFieldAccess idx] 
       generateJsonUpackingProjection : List (Name.Name, Type ()) -> Scala.Value
       generateJsonUpackingProjection names =
            Scala.Apply 
                    (Scala.Select selectExpr "select") 
                    (names 
                       |> List.indexedMap (\i (name, fType) -> Scala.ArgValue Nothing <| (generateAsCall (generateCastIfPossible ctx fType (resultFieldAccess i)) name)))
    in
    case tpe of
        TypeIR.Function _ _ (TypeIR.Reference _ _ [itemsType]) -> 
            (getFieldInfoIfRecordType itemsType ctx.typesContextInfo) 
                |> Maybe.map generateJsonUpackingProjection
        _ -> Nothing        

mapListMapFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapListMapFunction ( _, args ) mapValue ctx =
    case args of    
        [ action, sourceRelation ] ->
            generateForListMap action sourceRelation ctx mapValue
        _ ->
            Scala.Literal (Scala.StringLit "List map scenario not supported")


generateForListMap : Value ta (Type ()) -> (Value ta (Type ())) -> ValueMappingContext -> Constants.MapValueType ta -> Scala.Value
generateForListMap projection sourceRelation ctx mapValue =
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case processLambdaWithRecordBody projection ctx mapValue of
           Just arguments -> 
              Scala.Apply (Scala.Select (mapValue sourceRelation ctx) "select") arguments
           Nothing ->
              Scala.Literal (Scala.StringLit "Unsupported map scenario 1")
     else 
        Scala.Literal (Scala.StringLit "Unsupported map scenario 2")

processLambdaWithRecordBody : Value ta (Type ()) -> ValueMappingContext -> Constants.MapValueType ta -> Maybe (List Scala.ArgValue)
processLambdaWithRecordBody functionExpr ctx mapValue =
    case functionExpr of
        ValueIR.Lambda (TypeIR.Function _ _  returnType) (ValueIR.AsPattern _ _ _) (ValueIR.Record _ fields) ->
             if isAnonymousRecordWithSimpleTypes returnType ctx.typesContextInfo
                || isTypeRefToRecordWithSimpleTypes returnType ctx.typesContextInfo  then
               Just (fields  
                        |> getFieldsInCorrectOrder returnType ctx
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

getFieldsInCorrectOrder : Type () -> ValueMappingContext -> Dict Name.Name (Value ta (Type ())) ->  List (Name.Name, (Value ta (Type ())))
getFieldsInCorrectOrder originalType ctx fields =
    case originalType of
        TypeIR.Reference _ _ [] ->
            (getFieldInfoIfRecordType originalType ctx.typesContextInfo)
                |> Maybe.map (\lst -> collectMaybeList (\(name, _) -> Dict.get name fields |> Maybe.map (\fieldvalue -> (name, fieldvalue))) lst)
                |> Maybe.withDefault Nothing
                |> Maybe.withDefault (Dict.toList fields)
        _ ->
            Dict.toList fields


mapJustFunction  : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapJustFunction  ( _, args ) mapValue ctx =
    case args of    
        [ justValue ] ->
            mapValue justValue ctx 
        _ ->
            Scala.Literal (Scala.StringLit "Maybe Just scenario not supported")

    
mapMaybeMapFunction  : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapMaybeMapFunction  ( _, args ) mapValue ctx =
    case args of    
        [ action, source ] ->
            mapMaybeMapCall action source mapValue ctx 
        _ ->
            Scala.Literal (Scala.StringLit "Maybe Just scenario not supported")

mapMaybeMapCall : Value ta (Type ()) -> Value ta (Type ()) -> (Constants.MapValueType ta) -> ValueMappingContext -> Scala.Value
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

mapMaybeWithDefaultFunction  : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapMaybeWithDefaultFunction  ( _, args ) mapValue ctx =
    case args of    
        [ defaultValue, value ] ->
            Constants.applySnowparkFunc "coalesce" [mapValue value ctx, mapValue defaultValue ctx]
        _ ->
            Scala.Literal (Scala.StringLit "Maybe.withDefault scenario not supported")


mapAggregateFunction : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapAggregateFunction  ( _, args ) mapValue ctx =
    case args of
        [ (ValueIR.Lambda _ (ValueIR.AsPattern _ _ firstParameterName ) ( ValueIR.Lambda _ lambdaPattern lambdaBody )),
         (ValueIR.Apply 
            _
            (ValueIR.Apply _
                    (ValueIR.Reference _ ([["morphir"],["s","d","k"]],[["aggregate"]], ["group","by"]))
                    (ValueIR.FieldFunction _  groupByCategory ))
            dfName) ] ->
            let
                lambdaInfo = 
                    { lambdaPattern = lambdaPattern
                    , lambdaBody = lambdaBody
                    , groupByName = groupByCategory
                    , firstParameter = firstParameterName
                    }
                variablesInfo = AggregateMapping.processAggregateLambdaBody lambdaInfo (mapValue, ctx)
                collection = Scala.Select (mapValue dfName ctx) "groupBy"
                dfGroupBy = Scala.Apply collection [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit (Name.toCamelCase groupByCategory)))]
                aggFunction = Scala.Select dfGroupBy "agg"
                groupBySum = Scala.Apply aggFunction variablesInfo.variable
                selectColumns = Constants.transformToArgsValue <| List.map (\x -> Constants.applySnowparkFunc "col" [x]) variablesInfo.columnNameList
                select = Scala.Apply (Scala.Select groupBySum "select") selectColumns
            in
            select
        _ ->
            Scala.Literal (Scala.StringLit "Aggregate scenario not supported")
    

mapNotFunctionCall  : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapNotFunctionCall  ( _, args ) mapValue ctx =
    case args of    
        [ value ] ->
               let
                  mappedValue = mapValue value ctx
                in
                Scala.UnOp "!" mappedValue
        _ ->
            Scala.Literal (Scala.StringLit "'Not' scenario not supported")


mapFloorFunctionCall : (IrValueType ta, List (IrValueType ta)) -> Constants.MapValueType ta -> ValueMappingContext -> Scala.Value
mapFloorFunctionCall  ( _, args ) mapValue ctx =
    case args of    
        [ value ] ->
               let
                  mappedValue = mapValue value ctx
                in
                Constants.applySnowparkFunc  "floor" [ mappedValue ]     
        _ ->
            Scala.Literal (Scala.StringLit "'floor' scenario not supported")