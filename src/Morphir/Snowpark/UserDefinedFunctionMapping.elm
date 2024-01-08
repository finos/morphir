module Morphir.Snowpark.UserDefinedFunctionMapping exposing (tryToConvertUserFunctionCall)

import Morphir.IR.FQName as FQName
import Morphir.IR.Name as Name
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as ValueIR exposing (Pattern(..), TypedValue, Value(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants as Constants exposing (ValueGenerationResult, applySnowparkFunc)
import Morphir.Snowpark.MappingContext
    exposing
        ( FunctionClassification(..)
        , ValueMappingContext
        , isAliasedBasicType
        , isBasicType
        , isFunctionReceivingDataFrameExpressions
        , isLocalFunctionName
        , isLocalVariableDefinition
        , isRecordWithSimpleTypes
        )
import Morphir.Snowpark.ReferenceUtils
    exposing
        ( errorValueAndIssue
        , getCustomTypeParameterFieldAccess
        , getFunctionInputTypes
        , scalaPathToModule
        )


tryToConvertUserFunctionCall : ( TypedValue, List TypedValue ) -> Constants.MapValueType -> ValueMappingContext -> ValueGenerationResult
tryToConvertUserFunctionCall ( func, args ) mapValue ctx =
    case func of
        ValueIR.Reference functionType functionName ->
            if isLocalFunctionName functionName ctx then
                let
                    funcReference =
                        Scala.Ref (scalaPathToModule functionName)
                            (functionName |> FQName.getLocalName |> Name.toCamelCase)

                    ( argsConverted, argsIssues ) =
                        args
                            |> List.map (\arg -> mapValue arg ctx)
                            |> List.unzip

                    argsToUse =
                        checkIfArgumentsNeedsToBeAdapted functionName functionType argsConverted ctx
                            |> List.map (Scala.ArgValue Nothing)

                    issues =
                        List.concat argsIssues
                in
                case argsToUse of
                    [] ->
                        ( funcReference, issues )

                    first :: rest ->
                        ( List.foldl (\a c -> Scala.Apply c [ a ]) (Scala.Apply funcReference [ first ]) rest, issues )

            else
                ( Scala.Throw (Scala.New [] "Exception" [ Scala.ArgValue Nothing (Scala.Literal (Scala.StringLit "Call not generated")) ])
                , [ "Call to function not generated: " ++ FQName.toString functionName ]
                )

        ValueIR.Constructor _ constructorName ->
            if isRecordWithSimpleTypes constructorName ctx.typesContextInfo then
                let
                    ( argsToUse, issues ) =
                        args
                            |> List.map (\arg -> mapValue arg ctx)
                            |> List.unzip
                in
                ( Constants.applySnowparkFunc "array_construct" argsToUse, List.concat issues )

            else if isLocalFunctionName constructorName ctx && List.length args > 0 then
                let
                    ( mappedArgs, issuesPerArg ) =
                        args
                            |> List.map (\arg -> mapValue arg ctx)
                            |> List.unzip

                    argsToUse =
                        mappedArgs
                            |> List.indexedMap (\i arg -> ( getCustomTypeParameterFieldAccess i, arg ))
                            |> List.concatMap (\( field, value ) -> [ Constants.applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit field) ], value ])

                    tagName =
                        constructorName |> FQName.getLocalName |> Name.toTitleCase

                    tag =
                        [ Constants.applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit "__tag") ]
                        , Constants.applySnowparkFunc "lit" [ Scala.Literal (Scala.StringLit tagName) ]
                        ]
                in
                ( Constants.applySnowparkFunc "object_construct" (tag ++ argsToUse), List.concat issuesPerArg )

            else
                errorValueAndIssue ("Constructor call not converted: `" ++ FQName.toString constructorName ++ "`")

        ValueIR.Variable _ funcName ->
            if
                List.member funcName ctx.parameters
                    || isLocalVariableDefinition funcName ctx
            then
                let
                    ( mappedArgs, issuesPerArg ) =
                        args
                            |> List.map (\arg -> mapValue arg ctx)
                            |> List.unzip

                    argsToUse =
                        mappedArgs
                            |> List.map (Scala.ArgValue Nothing)
                in
                case argsToUse of
                    [] ->
                        ( Scala.Variable (Name.toCamelCase funcName), [] )

                    first :: rest ->
                        ( List.foldl
                            (\a c -> Scala.Apply c [ a ])
                            (Scala.Apply (Scala.Variable (Name.toCamelCase funcName)) [ first ])
                            rest
                        , List.concat issuesPerArg
                        )

            else
                errorValueAndIssue "Call to variable function not generated"

        _ ->
            errorValueAndIssue "Call not generated"


checkIfArgumentsNeedsToBeAdapted :
    FQName.FQName
    -> Type ()
    -> List Scala.Value
    -> ValueMappingContext
    -> List Scala.Value
checkIfArgumentsNeedsToBeAdapted invokedFunctionName functionType args ctx =
    let
        inPlainScalaFunction =
            ctx.currentFunctionClassification
                == FromComplexValuesToDataFrames
                || ctx.currentFunctionClassification
                == FromComplexToValues
    in
    if
        inPlainScalaFunction
            && isFunctionReceivingDataFrameExpressions invokedFunctionName ctx
    then
        getFunctionInputTypes functionType
            |> Maybe.map (\inputTypes -> List.map2 (adaptArgumentToDfExpr ctx) args inputTypes)
            |> Maybe.withDefault args

    else
        args


adaptArgumentToDfExpr : ValueMappingContext -> Scala.Value -> Type () -> Scala.Value
adaptArgumentToDfExpr ctx arg targetArgType =
    if isBasicType targetArgType || isAliasedBasicType targetArgType ctx.typesContextInfo then
        applySnowparkFunc "lit" [ arg ]

    else
        arg
