module Morphir.Snowpark.MapFunctionsMapping exposing (mapFunctionsMapping
                                                     , dataFrameMappings
                                                     , MappingFunctionType
                                                     , FunctionMappingTable
                                                     , listFunctionName
                                                     , mapUncurriedFunctionCall
                                                     , basicsFunctionName)

import Dict as Dict exposing (Dict)
import Morphir.Scala.AST as Scala
import Morphir.IR.Type as TypeIR exposing (Type)
import Morphir.IR.Value as ValueIR exposing (Pattern(..), Value(..), valueAttribute, TypedValue)
import Morphir.IR.Name as Name
import Morphir.IR.FQName as FQName
import Morphir.Snowpark.AggregateMapping as AggregateMapping
import Morphir.Snowpark.JoinMapping as JoinMapping
import Morphir.Snowpark.Constants as Constants exposing (applySnowparkFunc, ValueGenerationResult)
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue)
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
import Morphir.Snowpark.ReferenceUtils exposing (errorValueAndIssue
                                                , getListTypeParameter
                                                , isTypeReferenceToSimpleTypesRecord
                                                , scalaPathToModule )
import Morphir.Snowpark.UserDefinedFunctionMapping exposing (tryToConvertUserFunctionCall)
import Morphir.Snowpark.Utils exposing (collectMaybeList)
import Morphir.Snowpark.Operatorsmaps exposing (mapOperator)
import Morphir.Snowpark.LetMapping exposing (collectNestedLetDeclarations)
import Morphir.Snowpark.MappingContext exposing (addLocalDefinitions)
import Morphir.IR.Type as Type
import Morphir.IR.Name as Name

type alias MappingFunctionType = (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult

type alias FunctionMappingTable = Dict FQName.FQName MappingFunctionType

listFunctionName : Name.Name -> FQName.FQName
listFunctionName simpleName = 
    ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], simpleName )

maybeFunctionName : Name.Name -> FQName.FQName
maybeFunctionName simpleName = 
    ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], simpleName )

basicsFunctionName : Name.Name -> FQName.FQName
basicsFunctionName simpleName =
   ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], simpleName )

stringsFunctionName : Name.Name -> FQName.FQName
stringsFunctionName simpleName =
   ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], simpleName )

dataFrameMappings : FunctionMappingTable
dataFrameMappings =
    [ ( listFunctionName [ "member" ], mapListMemberFunction)
    , ( listFunctionName [ "map" ], mapListMapFunction )
    , ( listFunctionName [ "filter" ], mapListFilterFunction ) 
    , ( listFunctionName [ "filter", "map"], mapListFilterMapFunction ) 
    , ( listFunctionName [ "concat", "map"], mapListConcatMapFunction ) 
    , ( listFunctionName [ "concat" ], mapListConcatFunction ) 
    , ( listFunctionName [ "sum" ], mapListSumFunction )
    , ( listFunctionName [ "length" ], mapListLengthFunction )
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
    , ( basicsFunctionName ["min"] , mapMinMaxFunctionCall ("min", "<"))
    , ( basicsFunctionName ["max"] , mapMinMaxFunctionCall ("max", ">"))
    , ( basicsFunctionName ["to", "float"] , mapToFloatFunctionCall )
    , ( stringsFunctionName ["concat"] , mapStringConcatFunctionCall )
    , ( stringsFunctionName ["to", "upper"] , mapStringCaseCall ("String.toUpper", "upper") )
    , ( stringsFunctionName ["to", "lower"] , mapStringCaseCall ("String.toLower", "lower") )
    , ( stringsFunctionName ["reverse"] , mapStringReverse )
    , ( stringsFunctionName ["replace"] , mapStringReplace )    
    , ( stringsFunctionName ["starts", "with"] , mapStartsEndsWith ("String.statsWith", "startswith") )
    , ( stringsFunctionName ["ends", "with"] , mapStartsEndsWith ("String.endsWith", "endswith") )
    , ( ([["morphir"], ["s","d","k"]], [["aggregate"]], ["aggregate"]), mapAggregateFunction )
    ]
        |> Dict.fromList

mapFunctionsMapping : TypedValue -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapFunctionsMapping value mapValue ctx =
    case value of
        ValueIR.Apply _ function arg ->
            mapUncurriedFunctionCall (ValueIR.uncurryApply function arg) mapValue dataFrameMappings ctx
        _ ->
            errorValueAndIssue "Unsupported function mapping"

getFullNameIfReferencedElement : TypedValue -> Maybe FQName.FQName
getFullNameIfReferencedElement value =
    case value of
        ValueIR.Reference _ fullName ->
            Just fullName
        ValueIR.Constructor _ fullName ->
            Just fullName
        _ ->
            Nothing

mapUncurriedFunctionCall : (TypedValue, List TypedValue) -> Constants.MapValueType -> FunctionMappingTable -> ValueMappingContext -> ValueGenerationResult
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

getInliningFunctionIfRequired : ValueMappingContext -> FQName.FQName -> Maybe MappingFunctionType
getInliningFunctionIfRequired ctx name =
   Dict.get name ctx.globalValuesToInline
      |> Maybe.map (\definition ->
                        \(_, args) mapValue innerCtx ->
                            let
                                (mappedArgs, argsIssues) = 
                                    args
                                        |> List.map (\arg -> mapValue arg ctx)
                                        |> List.unzip
                                convertedArgs = 
                                    List.map2 (\arg (paramName, _, _) -> (paramName, arg)) mappedArgs definition.inputTypes
                                        
                                newCtx = 
                                    convertedArgs
                                        |> List.foldr (\(paramName, value) currentCtx -> 
                                                            addReplacementForIdentifier paramName value currentCtx) innerCtx 
                                (mappedBody, mappedBodyIssues) =
                                    mapValue definition.body newCtx
                            in
                            ( mappedBody, mappedBodyIssues ++ (List.concat argsIssues)))


mapListMemberFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListMemberFunction ( _, args ) mapValue ctx =
    case args of
        [ value, sourceRelation ] ->
            let
                (variable, variableIssues) =
                    mapValue value ctx
                (applySequence, sourceRelationIssues) =
                    mapValue sourceRelation ctx
                issues =
                    variableIssues ++ sourceRelationIssues
            in
            ( Scala.Apply (Scala.Select variable "in") [ Scala.ArgValue Nothing applySequence ], issues)
        _ ->
            errorValueAndIssue "`List.member` scenario not converted" 

mapListConcatMapFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListConcatMapFunction ( _, args ) mapValue ctx =
    case args of    
        [ filterAction, sourceRelation ] ->
            generateForConcatMap filterAction sourceRelation ctx mapValue
        _ ->
            errorValueAndIssue "List concatMap scenario not supported" 

generateForConcatMap : TypedValue -> TypedValue -> ValueMappingContext -> (Constants.MapValueType) -> ValueGenerationResult
generateForConcatMap action sourceRelation ctx mapValue =
    case (action, ValueIR.valueAttribute sourceRelation) of
        (ValueIR.Lambda ((TypeIR.Function _ fromType toType) as lambdaFunctionType) (AsPattern _ _ lambdaParam) body, sourceRelationType) ->
            if isCandidateForDataFrame sourceRelationType ctx.typesContextInfo && 
               isCandidateForDataFrame toType ctx.typesContextInfo then
               let 
                    contextForBody = 
                        isTypeReferenceToSimpleTypesRecord fromType ctx.typesContextInfo
                            |> Maybe.map (\(path, name) -> addReplacementForIdentifier lambdaParam (Scala.Ref path (Name.toTitleCase name)) ctx)
                            |> Maybe.withDefault ctx
                    (mappedBody, bodyIssues) = 
                        mapValue body contextForBody
                    selectArg =
                        (Scala.Apply 
                               (Scala.Select mappedBody "as") 
                               [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "result")) ])
                    (mappedSourceRelation, sourceIssues) =
                        mapValue sourceRelation ctx
                    flattenedDataFrame =
                        (Scala.Apply
                            (Scala.Select 
                                (Scala.Apply 
                                    (Scala.Select mappedSourceRelation "select") [Scala.ArgValue Nothing selectArg])
                                "flatten")
                            [Scala.ArgValue Nothing (applySnowparkFunc "col" [ Scala.Literal (Scala.StringLit "result") ])])
                    finalProjection = generateProjectionForArrayColumnIfRequired lambdaFunctionType ctx flattenedDataFrame "value"
                in
                (Maybe.withDefault flattenedDataFrame finalProjection, bodyIssues ++ sourceIssues)
            else
                errorValueAndIssue "List.concatMap scenario not supported"
        _ ->
            errorValueAndIssue "List.concatMap scenario not supported"

mapListConcatFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListConcatFunction ( _, args ) mapValue ctx =
    case args of    
        [ elements ] ->
            generateForListConcat elements ctx mapValue
        _ ->
            errorValueAndIssue "List concat scenario not supported"

generateForListConcat : TypedValue -> ValueMappingContext -> (Constants.MapValueType) -> ValueGenerationResult
generateForListConcat expr ctx mapValue =
    case expr of
        ValueIR.List (TypeIR.Reference _ _ [TypeIR.Reference _ _ [innerType]]) elements ->
              if isTypeRefToRecordWithSimpleTypes innerType ctx.typesContextInfo &&
                  hasFunctionToDfOpertions elements ctx then
                let 
                    (convertedItems, itemsIssues) = 
                            elements 
                                |> List.map (\item -> mapValue item ctx)
                                |> List.unzip
                in
                ( applySnowparkFunc "callBuiltin" [(Scala.Literal (Scala.StringLit "array_flatten")),  applySnowparkFunc "array_construct" convertedItems]
                , List.concat itemsIssues)
               else 
                 generateUnionAllWithMappedElements elements ctx mapValue
        _ ->
            errorValueAndIssue "List.concat case not supported"


generateUnionAllWithMappedElements : List TypedValue -> ValueMappingContext -> (Constants.MapValueType) -> ValueGenerationResult
generateUnionAllWithMappedElements elements ctx mapValue =
    case elements of
        first::rest -> 
            let 
                (firstMapped, firstIssues) = 
                    mapValue first ctx
                in
                rest
                    |> (List.foldl (\current (result, issues) ->
                                       let
                                          (mappedValue, valueIssues) = 
                                            mapValue current ctx
                                       in 
                                       ((Scala.Apply (Scala.Select result "unionAll") [ Scala.ArgValue Nothing mappedValue] ), issues ++ valueIssues))
                                   (firstMapped, firstIssues))
        _  ->
            errorValueAndIssue "List.concat case not supported"

hasFunctionToDfOpertions : List (Value a (Type ())) -> ValueMappingContext -> Bool
hasFunctionToDfOpertions listElements ctx =
    case listElements of
        (((ValueIR.Apply _ f a ))::_) -> 
            case ValueIR.uncurryApply f a of
                (ValueIR.Reference _ fullName , _) -> isFunctionReturningDataFrameExpressions fullName ctx
                _ -> 
                    False
        _ -> 
            False


mapBasicsFunctionCall : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapBasicsFunctionCall ( name, args ) mapValue ctx =
    case (name, args) of    
        (ValueIR.Reference _ fullFuncName, [ left, right ]) ->
            mapForOperatorCall (FQName.getLocalName fullFuncName) left right mapValue ctx
        _ ->
            errorValueAndIssue  "Basics function scenario not supported"


mapForOperatorCall : Name.Name -> TypedValue -> TypedValue -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapForOperatorCall optname left right mapValue ctx =
    case (optname, left, right) of
        (["equal"], _ , ValueIR.Constructor _ ([ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ])) -> 
            let 
                (mappedLeft, mappedLeftIssues) =
                    mapValue left ctx
            in
            (Scala.Select mappedLeft "is_null", mappedLeftIssues)
        ([ "not", "equal" ], _ , ValueIR.Constructor _ ([ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "nothing" ])) -> 
            let 
                (mappedLeft, mappedLeftIssues) =
                    mapValue left ctx
            in
            (Scala.Select mappedLeft "is_not_null", mappedLeftIssues)
        _ ->
            let
                (leftValue, leftIssues) =
                    mapValue left ctx
                (rightValue, rightIssues) =
                    mapValue right ctx
                operatorname =
                    mapOperator optname
                issues =
                    leftIssues ++ rightIssues
            in
            (Scala.BinOp leftValue operatorname rightValue, issues)



whenConditionElseValueCall : Scala.Value -> Scala.Value -> Scala.Value -> Scala.Value
whenConditionElseValueCall condition thenExpr elseExpr =
   Scala.Apply (Scala.Select (Constants.applySnowparkFunc "when" [condition, thenExpr]) "otherwise") 
               [Scala.ArgValue Nothing elseExpr]


mapListSumFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListSumFunction ( _, args ) mapValue ctx =
    case args of    
        [ elements ] ->
            generateForListSum elements ctx mapValue
        _ ->
            errorValueAndIssue "List sum scenario not supported"

mapListLengthFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListLengthFunction ( _, args ) mapValue ctx =
    case args of    
        [ elements ] ->
            if isCandidateForDataFrame (ValueIR.valueAttribute elements) ctx.typesContextInfo then
                let
                    (mappedCollection, collectionIssues) =
                        mapValue elements ctx
                in
                (Scala.Select mappedCollection "count", collectionIssues)
            else
                errorValueAndIssue "`List.length` scenario not supported"
        _ ->
            errorValueAndIssue "`List.length` scenario not supported"

generateForListSum : TypedValue -> ValueMappingContext -> Constants.MapValueType -> ValueGenerationResult
generateForListSum collection ctx mapValue =
    case collection of
        ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "map" ] )) _) sourceRelation ->
            if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
                case mapValue collection ctx of
                    (Scala.Apply col [Scala.ArgValue argName projectedExpr], issues) ->
                        let
                            resultName = Scala.Literal (Scala.StringLit "result")
                            asCall =  Scala.Apply (Scala.Select projectedExpr "as") [Scala.ArgValue Nothing resultName]
                            newSelect = Scala.Apply col [Scala.ArgValue argName asCall]
                            sumCall = Constants.applySnowparkFunc "coalesce" 
                                                                  [ Constants.applySnowparkFunc "sum" [Constants.applySnowparkFunc "col" [resultName]]
                                                                  , Constants.applySnowparkFunc "lit" [ Scala.Literal (Scala.IntegerLit 0)] ]
                            selectResult = Scala.Apply (Scala.Select newSelect "select") [Scala.ArgValue Nothing sumCall]
                        in
                        ( Scala.Apply 
                                (Scala.Select (Scala.Select (Scala.Select selectResult "first") "get") "getDouble") 
                                [ Scala.ArgValue Nothing (Scala.Literal (Scala.IntegerLit 0)) ]
                        , issues)
                            
                    _ ->
                        errorValueAndIssue "Unsupported sum scenario"
            else 
                errorValueAndIssue "Unsupported sum scenario"
        _ -> 
            errorValueAndIssue "Unsupported sum scenario"


mapListFilterFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListFilterFunction ( _, args ) mapValue ctx =
    case args of    
        [ filter, sourceRelation ] ->
            generateForListFilter filter sourceRelation ctx mapValue
        _ ->
            errorValueAndIssue "List filter scenario not supported"


generateForListFilter : TypedValue -> TypedValue -> ValueMappingContext -> Constants.MapValueType -> ValueGenerationResult
generateForListFilter predicate sourceRelation ctx mapValue =
    let
        (mappedSourceRelation, sourceRelationIssues) =
            mapValue sourceRelation ctx
        generateFilterCall (functionExpr, issues) =
             ( Scala.Apply 
                    (Scala.Select mappedSourceRelation "filter") 
                    [Scala.ArgValue Nothing functionExpr]
              , issues ++ sourceRelationIssues )
    in
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case predicate of
           ValueIR.Lambda _ _ bodyExpr ->
              generateFilterCall <| mapValue bodyExpr ctx
           ValueIR.Reference (TypeIR.Function _ fromType _) functionName ->
                case (isLocalFunctionName functionName ctx, generateRecordTypeWrapperExpression fromType ctx) of
                    (True, Just typeRefExpr) ->                        
                        (generateFilterCall <| 
                            (Scala.Apply (Scala.Ref (scalaPathToModule functionName) (functionName |> FQName.getLocalName |> Name.toCamelCase)) 
                                        [Scala.ArgValue Nothing typeRefExpr], []))
                    _ -> 
                        errorValueAndIssue "Unsupported filter function with referenced function" 
           (ValueIR.Apply ((Type.Function _ fromTpe toType) as tpe) _ _) as call ->
                let
                    newLambda = 
                        (ValueIR.Lambda 
                            tpe 
                            (ValueIR.AsPattern fromTpe (ValueIR.WildcardPattern fromTpe) [ "_t" ])
                            (ValueIR.Apply toType call (ValueIR.Variable fromTpe [ "_t" ])))
                in
                generateForListFilter newLambda sourceRelation ctx mapValue
           _ ->
              errorValueAndIssue "Unsupported filter function scenario" 
     else 
        errorValueAndIssue  "Unsupported filter scenario"


mapListFilterMapFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListFilterMapFunction ( _, args ) mapValue ctx =
    case args of    
        [ filter, sourceRelation ] ->
            generateForListFilterMap filter sourceRelation ctx mapValue
        _ ->
            errorValueAndIssue "List filterMap scenario not supported"


generateForListFilterMap : TypedValue -> TypedValue -> ValueMappingContext -> Constants.MapValueType -> ValueGenerationResult
generateForListFilterMap predicate sourceRelation ctx mapValue =
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case predicate of
           ValueIR.Lambda tpe _ binExpr ->
              let 
                  (mappedBinExpr, issuesExpr) = 
                      mapValue binExpr ctx
                  selectColumnAlias = 
                       Scala.Apply (Scala.Select mappedBinExpr "as ") [ Scala.ArgValue Nothing resultId ]
                  ( mappedSourceRelation, sourceRelationIssues ) =
                       mapValue sourceRelation ctx
                  selectCall = 
                       Scala.Apply (Scala.Select mappedSourceRelation "select") [Scala.ArgValue Nothing <| selectColumnAlias]
                  resultId = 
                       Scala.Literal <| Scala.StringLit "result"
                  isNotNullCall = 
                       Scala.Select (Constants.applySnowparkFunc "col" [ resultId ]) "is_not_null"
                  filterCall = 
                       Scala.Apply (Scala.Select selectCall "filter") [Scala.ArgValue Nothing isNotNullCall]
              in
              ( Maybe.withDefault filterCall (generateProjectionForArrayColumnIfRequired  tpe ctx filterCall "result")
              , issuesExpr ++ sourceRelationIssues)
           _ ->
              let 
                  tpe = ValueIR.valueAttribute predicate
                  recordReference =   getListTypeParameter (valueAttribute sourceRelation)
                                        |> Maybe.map (\t -> (getLocalVariableIfDataFrameReference t ctx))
                                        |> Maybe.withDefault Nothing
                                        |> Maybe.map Scala.Variable
                                        |> Maybe.withDefault (Scala.Literal Scala.NullLit)
                  (mappedPredicate, predicateIssues) = 
                      mapValue predicate ctx
                  predicateApplication = 
                    Scala.Apply mappedPredicate [Scala.ArgValue Nothing recordReference]
                  selectColumnAlias = 
                       Scala.Apply (Scala.Select predicateApplication "as ") [ Scala.ArgValue Nothing resultId ]
                  ( mappedSourceRelation, sourceRelationIssues ) =
                       mapValue sourceRelation ctx
                  selectCall = 
                       Scala.Apply (Scala.Select mappedSourceRelation "select") [Scala.ArgValue Nothing <| selectColumnAlias]
                  resultId = 
                       Scala.Literal <| Scala.StringLit "result"
                  isNotNullCall = 
                       Scala.Select (Constants.applySnowparkFunc "col" [ resultId ]) "is_not_null"
                  filterCall = 
                       Scala.Apply (Scala.Select selectCall "filter") [Scala.ArgValue Nothing isNotNullCall]
              in
              (Maybe.withDefault filterCall (generateProjectionForArrayColumnIfRequired  tpe ctx filterCall "result")
              , predicateIssues ++ sourceRelationIssues)
     else 
        errorValueAndIssue "Unsupported filterMap scenario"

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

mapListMapFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapListMapFunction ( _, args ) mapValue ctx =
    case args of    
        [ action, sourceRelation ] ->
            generateForListMap action sourceRelation ctx mapValue
        _ ->
            errorValueAndIssue "List map scenario not supported"


generateForListMap : TypedValue -> TypedValue -> ValueMappingContext -> Constants.MapValueType -> ValueGenerationResult
generateForListMap projection sourceRelation ctx mapValue =
    if isCandidateForDataFrame (valueAttribute sourceRelation) ctx.typesContextInfo then
        case processLambdaWithRecordBody projection ctx mapValue of
           Just (arguments, argsIssues) ->
              let
                (mappedSourceResult, issues) =
                    mapValue sourceRelation ctx
              in     
              (Scala.Apply (Scala.Select mappedSourceResult "select") arguments, issues ++ (List.concat argsIssues))
           Nothing ->
              errorValueAndIssue "Unsupported map scenario for data frame parameter"
     else 
        errorValueAndIssue "Unsupported map scenario"

isJoinFunction : (Value ta (Type ())) -> Bool
isJoinFunction value =
    case value of
            ValueIR.Apply _ (ValueIR.Apply _ (ValueIR.Apply _ ( ValueIR.Reference _  ([["morphir"],["s","d","k"]],[["list"]], name)) _) _ ) _ ->
                if String.contains "Join" (Name.toCamelCase name) then
                    True
                else
                    False
            _ ->
                False

processLambdaWithRecordBody : TypedValue -> ValueMappingContext -> Constants.MapValueType -> Maybe ((List Scala.ArgValue, List (List GenerationIssue)))
processLambdaWithRecordBody functionExpr ctx mapValue =
    case functionExpr of
        ValueIR.Lambda (TypeIR.Function _ _  returnType) (ValueIR.AsPattern _ _ _) (ValueIR.Record _ fields) ->
             if isAnonymousRecordWithSimpleTypes returnType ctx.typesContextInfo
                || isTypeRefToRecordWithSimpleTypes returnType ctx.typesContextInfo  then
               processMapRecordFields fields returnType ctx mapValue
                        
             else
                Nothing
        ValueIR.Lambda (TypeIR.Function _ _  returnType) (ValueIR.AsPattern _ _ _) expr ->
             if isBasicType returnType then
                let 
                    (mappedBody, mappedBodyIssues) =
                        mapValue expr ctx
                in
                Just  ([Scala.ArgValue Nothing mappedBody], [ mappedBodyIssues ]) 
             else if isAnonymousRecordWithSimpleTypes returnType ctx.typesContextInfo
                     || isTypeRefToRecordWithSimpleTypes returnType ctx.typesContextInfo then
                processLambdaBodyOfNonRecordLambda expr  ctx mapValue
             else  
                Nothing
        ValueIR.FieldFunction _ _ ->
            let
                (mappedFunctionExpr, mappedFunctionExprIssues) =
                    mapValue functionExpr ctx
            in
            Just  ([ Scala.ArgValue Nothing mappedFunctionExpr ], [ mappedFunctionExprIssues ])
        _ ->
            Nothing


processMapRecordFields : Dict (Name.Name) TypedValue -> Type () -> ValueMappingContext -> (Constants.MapValueType) -> Maybe ( List Scala.ArgValue, List (List GenerationIssue) )
processMapRecordFields fields returnType ctx mapValue =
    Just (fields  
             |> getFieldsInCorrectOrder returnType ctx
             |> List.map (\(fieldName, value) -> 
                                 (Name.toCamelCase fieldName, (mapValue value ctx)))
             |> List.map (\(fieldName, (value, issues)) ->  
                                 ((Scala.Apply 
                                     (Scala.Select value  "as") 
                                     [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit fieldName))])
                                 , issues))
             |> List.map (\(value, issues) -> (Scala.ArgValue Nothing value, issues))
             |> List.unzip)

processLambdaBodyOfNonRecordLambda : TypedValue -> ValueMappingContext -> Constants.MapValueType -> Maybe ((List Scala.ArgValue, List (List GenerationIssue)))
processLambdaBodyOfNonRecordLambda body ctx mapValue =
    case body of
        (ValueIR.LetDefinition _ _ _ _) as topDefinition ->
            let 
                (letDecls, letBodyExpr) = 
                    collectNestedLetDeclarations topDefinition []
                (newCtx, resultIssues) = 
                    letDecls
                        |> List.foldr 
                                (\(name, def) (currentCtx, currentIssues) -> 
                                        let
                                            (mappedDecl, issues) =
                                                mapValue def.body currentCtx
                                            newIssues =
                                                currentIssues ++ issues
                                        in
                                        ( addReplacementForIdentifier name mappedDecl currentCtx
                                        , newIssues))
                                (ctx ,[])
            in
            case letBodyExpr of
                ValueIR.Record recordType fields ->
                    processMapRecordFields fields recordType newCtx mapValue
                        |> Maybe.map (\(args, issuesLst) -> (args, issuesLst ++ [resultIssues]))
                _ ->
                    Nothing

        _ ->
            Nothing

getFieldsInCorrectOrder : Type () -> ValueMappingContext -> Dict Name.Name TypedValue ->  List (Name.Name, TypedValue)
getFieldsInCorrectOrder originalType ctx fields =
    case originalType of
        TypeIR.Reference _ _ [] ->
            (getFieldInfoIfRecordType originalType ctx.typesContextInfo)
                |> Maybe.map (\lst -> 
                                collectMaybeList 
                                    (\(name, _) -> Dict.get name fields 
                                                        |> Maybe.map (\fieldvalue -> (name, fieldvalue))) 
                                    lst)
                |> Maybe.withDefault Nothing
                |> Maybe.withDefault (Dict.toList fields)
        _ ->
            Dict.toList fields


mapJustFunction  : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapJustFunction  ( _, args ) mapValue ctx =
    case args of    
        [ justValue ] ->
            mapValue justValue ctx 
        _ ->
            errorValueAndIssue "Maybe Just scenario not supported"

    
mapMaybeMapFunction  : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapMaybeMapFunction  ( _, args ) mapValue ctx =
    case args of    
        [ action, source ] ->
            mapMaybeMapCall action source mapValue ctx 
        _ ->
            errorValueAndIssue "`Maybe.Just` scenario not supported"

mapMaybeMapCall : TypedValue -> TypedValue -> (Constants.MapValueType) -> ValueMappingContext -> ValueGenerationResult
mapMaybeMapCall action maybeValue mapValue ctx =
    case action of
        ValueIR.Lambda _ (AsPattern _ (WildcardPattern _) lambdaParam) body ->
            let
                (convertedValue, maybeValueIssues) =
                        mapValue maybeValue ctx
                newReplacements =
                        Dict.fromList [(lambdaParam, convertedValue)]
                (lambdaBody, lambdaIssues) = 
                        mapValue body { ctx | inlinedIds  = Dict.union ctx.inlinedIds newReplacements }
                elseLiteral = 
                        Constants.applySnowparkFunc "lit" [(Scala.Literal (Scala.NullLit))]
                issues = 
                        maybeValueIssues ++ lambdaIssues
            in
            (whenConditionElseValueCall (Scala.Select convertedValue "is_not_null") lambdaBody elseLiteral, issues)
        ValueIR.Reference _ _ ->
            let
               (convertedValue, maybeValueIssues) = 
                    mapValue maybeValue ctx
               elseLiteral = 
                    Constants.applySnowparkFunc "lit" [(Scala.Literal (Scala.NullLit))]
               (convertedFunctionApplication, funcApplicationIssues) =  
                    mapValue (ValueIR.Apply (ValueIR.valueAttribute maybeValue) action maybeValue) ctx
               issues = 
                        maybeValueIssues ++ funcApplicationIssues
            in
            (whenConditionElseValueCall (Scala.Select convertedValue "is_not_null") convertedFunctionApplication elseLiteral, issues)
        _ -> 
            errorValueAndIssue  "Unsupported `Maybe.map` call"

mapMaybeWithDefaultFunction  : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapMaybeWithDefaultFunction  ( _, args ) mapValue ctx =
    case args of    
        [ defaultValue, value ] ->
            let
                (mappedValue, valueIssues) = 
                    mapValue value ctx
                (mappedDefaultValue, defaultValueIssues) = 
                    mapValue defaultValue ctx
                issues =
                    valueIssues ++ defaultValueIssues
            in
            ( Constants.applySnowparkFunc "coalesce" [ mappedValue, mappedDefaultValue ], issues )
        _ ->
            errorValueAndIssue "Maybe.withDefault scenario not supported"


mapAggregateFunction : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
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
                (mappedDfName, dfNameIssues) = mapValue dfName ctx
                collection = Scala.Select mappedDfName "groupBy"
                dfGroupBy = Scala.Apply collection [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit (Name.toCamelCase groupByCategory)))]
                aggFunction = Scala.Select dfGroupBy "agg"
                groupBySum = Scala.Apply aggFunction variablesInfo.variable
                selectColumns = Constants.transformToArgsValue <| List.map (\x -> Constants.applySnowparkFunc "col" [x]) variablesInfo.columnNameList
                select = Scala.Apply (Scala.Select groupBySum "select") selectColumns
            in
            (select, dfNameIssues)
        _ ->
            errorValueAndIssue "Aggregate scenario not supported"
    
mapJoinFunction :  TypedValue -> TypedValue -> Constants.MapValueType -> ValueMappingContext  -> ValueGenerationResult
mapJoinFunction projection joinValue mapValue ctx =
    let
        (joinBody, joinBodyIssues) = 
            JoinMapping.processJoinBody joinValue mapValue ctx
        (joinProjection, joinProjectionIssues) = 
            JoinMapping.processJoinProjection projection mapValue ctx
        select = Scala.Select joinBody "select" 

        argAlias = Constants.transformToArgsValue joinProjection
    in
    (Scala.Apply select argAlias, joinProjectionIssues ++ joinBodyIssues)
    


mapNotFunctionCall  : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> (Scala.Value, List GenerationIssue)
mapNotFunctionCall  ( _, args ) mapValue ctx =
    case args of    
        [ value ] ->
               let
                  (mappedValue, issues) = mapValue value ctx
                in
                (Scala.UnOp "!" mappedValue, issues)
        _ ->
            (Scala.Literal (Scala.StringLit "'Not' scenario not supported"), ["'Not' scenario not supported"])


mapStringConcatFunctionCall : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapStringConcatFunctionCall  ( _, args ) mapValue ctx =
    case args of    
        [ ValueIR.List _ values ] ->
               let
                  (mappedItems, itemsIssues) = 
                                values
                                    |> List.map (\arg -> mapValue arg ctx)
                                    |> List.unzip
                  issues = List.concat itemsIssues
                in
                (Constants.applySnowparkFunc  "concat" mappedItems, issues)
        _ ->
            errorValueAndIssue "'String.concat' scenario not supported"

mapMinMaxFunctionCall : (String, String) -> (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapMinMaxFunctionCall (morphirName, operator) ( _, args ) mapValue ctx =
    case args of    
        [ value1, value2 ] ->
               let
                  (mappedValue1, value1Issues) = 
                        mapValue value1 ctx
                  (mappedValue2, value2Issues) =
                        mapValue value2 ctx
                  issues = 
                        value1Issues ++ value2Issues
                in
                ((Scala.Apply 
                    ((Scala.Select
                        (Constants.applySnowparkFunc "when" [ Scala.BinOp mappedValue1 operator mappedValue2, mappedValue1 ])
                        "otherwise"))
                      [ Scala.ArgValue Nothing mappedValue2 ])
                 , issues)
        _ ->
            errorValueAndIssue ("`" ++ morphirName ++ " scenario not supported")

mapToFloatFunctionCall : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapToFloatFunctionCall  ( _, args ) mapValue ctx =
    case args of    
        [ value ] ->
               let
                  (mappedValue, valueIssues) = mapValue value ctx
                in 
                (Constants.applySnowparkFunc  "as_double" [ mappedValue ], valueIssues)
        _ ->
            errorValueAndIssue "`toFloat` scenario not supported"

mapFloorFunctionCall : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapFloorFunctionCall  ( _, args ) mapValue ctx =
    case args of    
        [ value ] ->
               let
                  (mappedValue, valueIssues) = mapValue value ctx
                in
                (Constants.applySnowparkFunc  "floor" [ mappedValue ], valueIssues)
        _ ->
            errorValueAndIssue "'floor' scenario not supported"


mapStringCaseCall : (String, String) -> (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapStringCaseCall  (morphirName, spName) ( _, args ) mapValue ctx =
    case args of    
        [ value ] ->
               let
                  (mappedValue, valueIssues) = mapValue value ctx
                in
                (Constants.applySnowparkFunc  spName [ mappedValue ], valueIssues)
        _ ->
            errorValueAndIssue ("`" ++ morphirName ++ "` scenario not supported")

mapStartsEndsWith : (String, String) -> (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapStartsEndsWith  (morphirName, spName) ( _, args ) mapValue ctx =
    case args of    
        [ prefixOrSuffix, str ] ->
               let
                  (mappedStr, strIssues) = mapValue str ctx
                  (mappedPrefixOrSuffix, prefixOrIssues) = mapValue prefixOrSuffix ctx
                  issues = strIssues ++ prefixOrIssues
                in
                (Constants.applySnowparkFunc  spName [ mappedStr, mappedPrefixOrSuffix ], issues)
        _ ->
            errorValueAndIssue ("`" ++ morphirName ++ "` scenario not supported")

mapStringReverse : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapStringReverse ( _, args ) mapValue ctx =
    case args of    
        [ value ] ->
               let
                  (mappedValue, valueIssues) = mapValue value ctx
                in
                (Constants.applySnowparkFunc  "callBuiltin" [ (Scala.Literal (Scala.StringLit "reverse")), mappedValue ], valueIssues)
        _ ->
            errorValueAndIssue "`String.reverse` scenario not supported"

mapStringReplace : (TypedValue, List TypedValue) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
mapStringReplace ( _, args ) mapValue ctx =
    case args of    
        [ toReplace, replacement, value ] ->
               let
                  (mappedValue, valueIssues) = mapValue value ctx
                  (mappedToReplace, toReplaceIssues) = mapValue toReplace ctx
                  (mappedReplacement, replacementIssues) = mapValue replacement ctx
                  issues = valueIssues ++ toReplaceIssues ++ replacementIssues
                in
                (Constants.applySnowparkFunc  "replace" [ mappedValue, mappedToReplace, mappedReplacement ], issues)
        _ ->
            errorValueAndIssue "`String.replace` scenario not supported"