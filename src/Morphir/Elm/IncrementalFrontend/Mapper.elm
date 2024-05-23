module Morphir.Elm.IncrementalFrontend.Mapper exposing (Error(..), Errors, SourceLocation, mapDeclarationsToValue, mapFunction, mapTypeAnnotation)

import Dict exposing (Dict)
import Elm.Syntax.Declaration exposing (Declaration(..))
import Elm.Syntax.Expression as Expression exposing (Expression(..))
import Elm.Syntax.ModuleName as Elm
import Elm.Syntax.Node as Node exposing (Node(..))
import Elm.Syntax.Pattern as Pattern exposing (Pattern)
import Elm.Syntax.Range as Range
import Elm.Syntax.TypeAnnotation exposing (TypeAnnotation(..))
import Graph exposing (Graph)
import Morphir.Elm.IncrementalResolve as IncrementalResolve
import Morphir.Elm.ModuleName as ElmModuleName
import Morphir.Elm.ParsedModule as ParsedModule exposing (ParsedModule)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.KindOfName exposing (KindOfName(..))
import Morphir.IR.Literal as Literal
import Morphir.IR.Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.SDK.Basics as SDKBasics
import Morphir.IR.SDK.List as List
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Morphir.SDK.ResultList as ResultList
import Morphir.Type.Infer as Infer
import Set exposing (Set)


type alias Errors =
    List Error


type Error
    = EmptyApply SourceLocation
    | NotSupported SourceLocation String
    | RecordPatternNotSupported SourceLocation
      -- TODO figure out where this error needs to be
    | ResolveError SourceLocation IncrementalResolve.Error
    | SameNameAppearsMultipleTimesInPattern SourceLocation (Set String)
    | VariableNameCollision SourceLocation String
    | UnresolvedVariable SourceLocation String
    | TypeCheckError ModuleName Infer.TypeError


type alias SourceLocation =
    { moduleName : ElmModuleName
    , location : Range
    }


type alias Range =
    Range.Range


type alias ElmModuleName =
    ElmModuleName.ModuleName


type alias TypeAttribute =
    Bool


defaultTypeAttribute : TypeAttribute
defaultTypeAttribute =
    False


{-| Type alias to make it easier to change the specific value annotation used on each value node.
-}
type alias ValueAttribute =
    ()


{-| Value annotation used when a new value node is created.
-}
defaultValueAttribute : ValueAttribute
defaultValueAttribute =
    ()



-- Type Mappings


mapTypeAnnotation : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> Node TypeAnnotation -> Result Errors (Type TypeAttribute)
mapTypeAnnotation resolveTypeName (Node _ typeAnnotation) =
    case typeAnnotation of
        GenericType varName ->
            Ok (Type.Variable defaultTypeAttribute (varName |> Name.fromString))

        Typed (Node range ( moduleName, localName )) argNodes ->
            Result.map2
                (Type.Reference defaultTypeAttribute)
                (resolveTypeName moduleName localName Type |> Result.mapError (ResolveError (SourceLocation moduleName range) >> List.singleton))
                (argNodes
                    |> List.map (mapTypeAnnotation resolveTypeName)
                    |> ResultList.keepAllErrors
                    |> Result.mapError List.concat
                )

        Unit ->
            Ok (Type.Unit defaultTypeAttribute)

        Tupled typeAnnotationNodes ->
            typeAnnotationNodes
                |> List.map (mapTypeAnnotation resolveTypeName)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Type.Tuple defaultTypeAttribute)

        Record fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ argName, fieldTypeNode ) ->
                        mapTypeAnnotation resolveTypeName fieldTypeNode
                            |> Result.map (Type.Field (Name.fromString argName))
                    )
                |> ResultList.keepAllErrors
                |> Result.map (Type.Record defaultTypeAttribute)
                |> Result.mapError List.concat

        GenericRecord (Node _ argName) (Node _ fieldNodes) ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ ags, fieldTypeNode ) ->
                        mapTypeAnnotation resolveTypeName fieldTypeNode
                            |> Result.map (Type.Field (Name.fromString ags))
                    )
                |> ResultList.keepAllErrors
                |> Result.map (Type.ExtensibleRecord defaultTypeAttribute (Name.fromString argName))
                |> Result.mapError List.concat

        FunctionTypeAnnotation argTypeNode returnTypeNode ->
            Result.map2
                (Type.Function defaultTypeAttribute)
                (mapTypeAnnotation resolveTypeName argTypeNode)
                (mapTypeAnnotation resolveTypeName returnTypeNode)



-- Value Mappings


mapDeclarationsToValue : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> ParsedModule -> List (Node Declaration) -> Result Errors (List ( FQName, ( ( Maybe (Type ()), Value () () ), String ) ))
mapDeclarationsToValue resolveName parsedModule decls =
    let
        moduleName : Elm.ModuleName
        moduleName =
            ParsedModule.moduleName parsedModule
    in
    decls
        |> List.filterMap
            (\(Node range decl) ->
                case decl of
                    FunctionDeclaration function ->
                        let
                            valueName : Result Errors FQName
                            valueName =
                                function.declaration
                                    |> Node.value
                                    |> .name
                                    |> Node.value
                                    -- Local names are not expected to have a prefix so we pass in an empty module name
                                    |> (\localName ->
                                            resolveName [] localName Value
                                                |> Result.mapError (ResolveError (SourceLocation moduleName range) >> List.singleton)
                                       )

                            valueDef : Result Errors ( Maybe (Type ()), Value () () )
                            valueDef =
                                Node range function
                                    |> mapFunction resolveName moduleName Set.empty
                                    |> Result.map
                                        (\maybeTypedValueDef ->
                                            let
                                                -- modelers may or may not specify type information in the Elm code but it is mandatory
                                                maybeValueType : Maybe (Type ())
                                                maybeValueType =
                                                    if maybeTypedValueDef.outputType |> Type.typeAttributes then
                                                        Just (maybeTypedValueDef.outputType |> Type.mapTypeAttributes (always ()))

                                                    else
                                                        Nothing
                                            in
                                            ( maybeValueType, maybeTypedValueDef.body |> Value.mapValueAttributes (always ()) identity )
                                        )

                            valueDoc : String
                            valueDoc =
                                function.documentation
                                    |> Maybe.map (Node.value >> String.dropLeft 3 >> String.dropRight 2)
                                    |> Maybe.withDefault ""
                        in
                        valueDef
                            |> Result.map2 (\valName valDef -> ( valName, ( valDef, valueDoc ) )) valueName
                            |> Just

                    _ ->
                        Nothing
            )
        |> ResultList.keepAllErrors
        |> Result.mapError List.concat


mapExpression : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Set String -> Node Expression -> Result Errors (Value.Value TypeAttribute ValueAttribute)
mapExpression resolveReferenceName moduleName variables (Node range expr) =
    case expr of
        Expression.UnitExpr ->
            Value.Unit defaultValueAttribute |> Ok

        Expression.Application expNodes ->
            let
                toApply : List (Value.Value TypeAttribute ValueAttribute) -> Result Errors (Value.Value TypeAttribute ValueAttribute)
                toApply valuesReversed =
                    case valuesReversed of
                        [] ->
                            Err
                                [ SourceLocation moduleName range
                                    |> EmptyApply
                                ]

                        [ singleValue ] ->
                            Ok singleValue

                        lastValue :: restOfValuesReversed ->
                            toApply restOfValuesReversed
                                |> Result.map
                                    (\funValue ->
                                        Value.Apply defaultValueAttribute funValue lastValue
                                    )
            in
            expNodes
                |> List.map (mapExpression resolveReferenceName moduleName variables)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.andThen (List.reverse >> toApply)

        Expression.OperatorApplication op _ leftNode rightNode ->
            case op of
                "<|" ->
                    -- the purpose of this operator is cleaner syntax so it's not mapped to the IR
                    Result.map2 (Value.Apply defaultValueAttribute)
                        (mapExpression resolveReferenceName moduleName variables leftNode)
                        (mapExpression resolveReferenceName moduleName variables rightNode)

                "|>" ->
                    -- the purpose of this operator is cleaner syntax so it's not mapped to the IR
                    Result.map2
                        (Value.Apply defaultValueAttribute)
                        (mapExpression resolveReferenceName moduleName variables rightNode)
                        (mapExpression resolveReferenceName moduleName variables leftNode)

                _ ->
                    Result.map3 (\fun arg1 arg2 -> Value.Apply defaultValueAttribute (Value.Apply defaultValueAttribute fun arg1) arg2)
                        (mapOperator moduleName range op)
                        (mapExpression resolveReferenceName moduleName variables leftNode)
                        (mapExpression resolveReferenceName moduleName variables rightNode)

        Expression.FunctionOrValue modName localName ->
            if List.isEmpty modName && Set.member localName variables then
                Ok (Value.Variable defaultValueAttribute (Name.fromString localName))

            else
                localName
                    |> String.uncons
                    |> Result.fromMaybe [ NotSupported (SourceLocation moduleName range) "Empty value name" ]
                    |> Result.andThen
                        (\( firstChar, _ ) ->
                            if Char.isUpper firstChar then
                                case ( modName, localName ) of
                                    ( [], "True" ) ->
                                        Ok (Value.Literal defaultValueAttribute (Literal.BoolLiteral True))

                                    ( [], "False" ) ->
                                        Ok (Value.Literal defaultValueAttribute (Literal.BoolLiteral False))

                                    _ ->
                                        resolveReferenceName modName localName Constructor
                                            |> Result.mapError (ResolveError (SourceLocation moduleName range) >> List.singleton)
                                            |> Result.map (Value.Constructor defaultValueAttribute)

                            else
                                resolveReferenceName modName localName Value
                                    |> Result.mapError (ResolveError (SourceLocation moduleName range) >> List.singleton)
                                    |> Result.map (Value.Reference defaultValueAttribute)
                        )

        Expression.IfBlock condNode thenNode elseNode ->
            Result.map3 (Value.IfThenElse defaultValueAttribute)
                (mapExpression resolveReferenceName moduleName variables condNode)
                (mapExpression resolveReferenceName moduleName variables thenNode)
                (mapExpression resolveReferenceName moduleName variables elseNode)

        Expression.PrefixOperator op ->
            mapOperator moduleName range op

        Expression.Operator op ->
            mapOperator moduleName range op

        Expression.Integer value ->
            Ok (Value.Literal defaultValueAttribute (Literal.WholeNumberLiteral value))

        Expression.Hex value ->
            Ok (Value.Literal defaultValueAttribute (Literal.WholeNumberLiteral value))

        Expression.Floatable value ->
            Ok (Value.Literal defaultValueAttribute (Literal.FloatLiteral value))

        Expression.Negation arg ->
            case arg of
                Node _ exp ->
                    case exp of
                        Integer value ->
                            Ok (Value.Literal defaultValueAttribute (Literal.WholeNumberLiteral -value))

                        Floatable value ->
                            Ok (Value.Literal defaultValueAttribute (Literal.FloatLiteral -value))

                        _ ->
                            mapExpression resolveReferenceName moduleName variables arg
                                |> Result.map (SDKBasics.negate defaultValueAttribute defaultValueAttribute)

        Expression.Literal value ->
            Ok (Value.Literal defaultValueAttribute (Literal.StringLiteral value))

        Expression.CharLiteral value ->
            Ok (Value.Literal defaultValueAttribute (Literal.CharLiteral value))

        Expression.TupledExpression expNodes ->
            expNodes
                |> List.map (mapExpression resolveReferenceName moduleName variables)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.Tuple defaultValueAttribute)

        Expression.ParenthesizedExpression expNode ->
            mapExpression resolveReferenceName moduleName variables expNode

        Expression.LetExpression letBlock ->
            mapLetExpression
                resolveReferenceName
                moduleName
                variables
                letBlock

        Expression.CaseExpression caseBlock ->
            Result.map2 (Value.PatternMatch defaultValueAttribute)
                (mapExpression resolveReferenceName moduleName variables caseBlock.expression)
                (caseBlock.cases
                    |> List.map
                        (\( patternNode, bodyNode ) ->
                            mapPattern resolveReferenceName moduleName variables patternNode
                                |> Result.andThen
                                    (\( patternVariables, pattern ) ->
                                        mapExpression resolveReferenceName moduleName (variables |> Set.union patternVariables) bodyNode
                                            |> Result.map (\caseBody -> ( pattern, caseBody ))
                                    )
                        )
                    |> ResultList.keepAllErrors
                    |> Result.mapError List.concat
                )

        Expression.LambdaExpression lambda ->
            let
                curriedLambda : Set String -> List (Node Pattern) -> Node Expression -> Result Errors (Value.Value TypeAttribute ValueAttribute)
                curriedLambda lambdaVariables argNodes bodyNode =
                    case argNodes of
                        [] ->
                            mapExpression resolveReferenceName moduleName lambdaVariables bodyNode

                        firstArgNode :: restOfArgNodes ->
                            mapPattern resolveReferenceName moduleName lambdaVariables firstArgNode
                                |> Result.andThen
                                    (\( argVariables, argPattern ) ->
                                        curriedLambda (lambdaVariables |> Set.union argVariables) restOfArgNodes bodyNode
                                            |> Result.map (Value.Lambda defaultValueAttribute argPattern)
                                    )
            in
            curriedLambda variables lambda.args lambda.expression

        Expression.RecordExpr fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldValue ) ->
                        mapExpression resolveReferenceName moduleName variables fieldValue
                            |> Result.map (Tuple.pair (fieldName |> Name.fromString))
                    )
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map Dict.fromList
                |> Result.map (Value.Record defaultValueAttribute)

        Expression.ListExpr itemNodes ->
            itemNodes
                |> List.map (mapExpression resolveReferenceName moduleName variables)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.List defaultValueAttribute)

        Expression.RecordAccess targetNode fieldNameNode ->
            mapExpression resolveReferenceName moduleName variables targetNode
                |> Result.map
                    (\subjectValue ->
                        Value.Field defaultValueAttribute
                            subjectValue
                            (fieldNameNode |> Node.value |> Name.fromString)
                    )

        Expression.RecordAccessFunction fieldName ->
            Ok (Value.FieldFunction defaultValueAttribute (fieldName |> Name.fromString))

        Expression.RecordUpdateExpression (Node targetVarRange targetVarName) fieldNodes ->
            let
                wrapInUpdateRecord : Value TypeAttribute ValueAttribute -> Result (List Error) (Value TypeAttribute ValueAttribute)
                wrapInUpdateRecord targetValue =
                    fieldNodes
                        |> List.map Node.value
                        |> List.map
                            (\( Node _ fieldName, fieldValue ) ->
                                mapExpression resolveReferenceName moduleName variables fieldValue
                                    |> Result.map (Tuple.pair (fieldName |> Name.fromString))
                            )
                        |> ResultList.keepAllErrors
                        |> Result.mapError List.concat
                        |> Result.map Dict.fromList
                        |> Result.map
                            (Value.UpdateRecord
                                defaultValueAttribute
                                targetValue
                            )
            in
            if variables |> Set.member targetVarName then
                wrapInUpdateRecord (targetVarName |> Name.fromString |> Value.Variable defaultValueAttribute)

            else
                resolveReferenceName [] targetVarName Value
                    |> Result.mapError (ResolveError (SourceLocation moduleName targetVarRange) >> List.singleton)
                    |> Result.andThen (Value.Reference defaultValueAttribute >> wrapInUpdateRecord)

        Expression.GLSLExpression _ ->
            Err
                [ NotSupported
                    (SourceLocation moduleName range)
                    "GLSLExpression"
                ]


mapFunction : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Set String -> Node Expression.Function -> Result Errors (Value.Definition Bool ValueAttribute)
mapFunction resolveName moduleName variables (Node functionRange function) =
    let
        expression : Node Expression
        expression =
            Node
                functionRange
                (Expression.LambdaExpression
                    { args =
                        function.declaration
                            |> Node.value
                            |> .arguments
                    , expression =
                        function.declaration
                            |> Node.value
                            |> .expression
                    }
                )

        emptyDistribution : Distribution
        emptyDistribution =
            Library [ [ "empty" ] ] Dict.empty Package.emptyDefinition

        inferValue : Value () ValueAttribute -> Result Errors (Value () (Type ()))
        inferValue value =
            Infer.inferValue emptyDistribution value
                |> Result.map (Value.mapValueAttributes identity Tuple.second)
                |> Result.mapError
                    (TypeCheckError
                        (List.map Name.fromString moduleName)
                        >> List.singleton
                    )

        declaredOrInferredTypeResult : Value TypeAttribute ValueAttribute -> Result Errors (Type TypeAttribute)
        declaredOrInferredTypeResult value =
            case function.signature of
                Just (Node _ signature) ->
                    signature.typeAnnotation
                        |> mapTypeAnnotation resolveName
                        |> Result.map (Type.mapTypeAttributes (always True))

                Nothing ->
                    Value.mapValueAttributes (always ()) identity value
                        |> inferValue
                        |> Result.map (Value.valueAttribute >> Type.mapTypeAttributes (always True))
    in
    mapExpression resolveName moduleName variables expression
        |> Result.andThen
            (\value ->
                declaredOrInferredTypeResult value
                    |> Result.map
                        (\valueType ->
                            { inputTypes = []
                            , outputType = valueType
                            , body = value |> Value.mapValueAttributes (always False) identity
                            }
                        )
            )


mapPattern : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Set String -> Node Pattern -> Result Errors ( Set String, Value.Pattern ValueAttribute )
mapPattern nameResolver moduleName variables (Node range pattern) =
    case pattern of
        Pattern.AllPattern ->
            Ok ( Set.empty, Value.WildcardPattern defaultValueAttribute )

        Pattern.UnitPattern ->
            Ok ( Set.empty, Value.UnitPattern defaultValueAttribute )

        Pattern.CharPattern char ->
            Ok ( Set.empty, Value.LiteralPattern defaultValueAttribute (Literal.CharLiteral char) )

        Pattern.StringPattern string ->
            Ok ( Set.empty, Value.LiteralPattern defaultValueAttribute (Literal.StringLiteral string) )

        Pattern.IntPattern int ->
            Ok ( Set.empty, Value.LiteralPattern defaultValueAttribute (Literal.WholeNumberLiteral int) )

        Pattern.HexPattern int ->
            Ok ( Set.empty, Value.LiteralPattern defaultValueAttribute (Literal.WholeNumberLiteral int) )

        Pattern.FloatPattern float ->
            Ok ( Set.empty, Value.LiteralPattern defaultValueAttribute (Literal.FloatLiteral float) )

        Pattern.TuplePattern elemNodes ->
            mapListOfPatterns nameResolver moduleName variables elemNodes
                |> Result.map (Tuple.mapSecond (Value.TuplePattern defaultValueAttribute))

        Pattern.RecordPattern _ ->
            Err
                [ SourceLocation moduleName range
                    |> RecordPatternNotSupported
                ]

        Pattern.UnConsPattern headNode tailNode ->
            mapPattern nameResolver moduleName variables headNode
                |> Result.andThen
                    (\( pattern1Variables, headPattern ) ->
                        mapPattern nameResolver moduleName variables tailNode
                            |> Result.andThen
                                (\( pattern2Variables, tailPattern ) ->
                                    let
                                        overlappingVariableNames : Set String
                                        overlappingVariableNames =
                                            Set.intersect pattern1Variables pattern2Variables
                                    in
                                    if Set.isEmpty overlappingVariableNames then
                                        Ok ( Set.union pattern1Variables pattern2Variables, Value.HeadTailPattern defaultValueAttribute headPattern tailPattern )

                                    else
                                        Err [ SameNameAppearsMultipleTimesInPattern (SourceLocation moduleName range) overlappingVariableNames ]
                                )
                    )

        Pattern.ListPattern itemNodes ->
            let
                listToHeadTail : List (Value.Pattern ValueAttribute) -> Value.Pattern ValueAttribute
                listToHeadTail patternNodes =
                    case patternNodes of
                        [] ->
                            Value.EmptyListPattern defaultValueAttribute

                        headNode :: tailNodes ->
                            Value.HeadTailPattern defaultValueAttribute headNode (listToHeadTail tailNodes)
            in
            mapListOfPatterns nameResolver moduleName variables itemNodes
                |> Result.map (Tuple.mapSecond listToHeadTail)

        Pattern.VarPattern name ->
            if variables |> Set.member name then
                Err [ VariableNameCollision (SourceLocation moduleName range) name ]

            else
                Ok ( Set.singleton name, Value.AsPattern defaultValueAttribute (Value.WildcardPattern defaultValueAttribute) (Name.fromString name) )

        Pattern.NamedPattern qualifiedNameRef argNodes ->
            let
                fullyQualifiedName : Result Errors FQName
                fullyQualifiedName =
                    nameResolver qualifiedNameRef.moduleName qualifiedNameRef.name Constructor
                        |> Result.mapError (ResolveError (SourceLocation moduleName range) >> List.singleton)
            in
            case ( qualifiedNameRef.moduleName, qualifiedNameRef.name ) of
                ( [], "True" ) ->
                    Ok ( Set.empty, Value.LiteralPattern defaultValueAttribute (Literal.BoolLiteral True) )

                ( [], "False" ) ->
                    Ok ( Set.empty, Value.LiteralPattern defaultValueAttribute (Literal.BoolLiteral False) )

                _ ->
                    Result.map2
                        (\fqn ( vars, argPatterns ) -> ( vars, Value.ConstructorPattern defaultValueAttribute fqn argPatterns ))
                        fullyQualifiedName
                        (mapListOfPatterns nameResolver moduleName variables argNodes)

        Pattern.AsPattern subjectNode (Node aliasRange alias) ->
            mapPattern nameResolver moduleName variables subjectNode
                |> Result.andThen
                    (\( subjectVariables, subjectPattern ) ->
                        if subjectVariables |> Set.member alias then
                            Err [ SameNameAppearsMultipleTimesInPattern (SourceLocation moduleName aliasRange) (Set.singleton alias) ]

                        else if variables |> Set.member alias then
                            Err [ VariableNameCollision (SourceLocation moduleName aliasRange) alias ]

                        else
                            Ok
                                ( subjectVariables |> Set.insert alias
                                , Value.AsPattern defaultValueAttribute
                                    subjectPattern
                                    (Name.fromString alias)
                                )
                    )

        Pattern.ParenthesizedPattern childNode ->
            mapPattern nameResolver moduleName variables childNode


mapListOfPatterns : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Set String -> List (Node Pattern) -> Result Errors ( Set String, List (Value.Pattern ValueAttribute) )
mapListOfPatterns nameResolver moduleName variables patternNodes =
    patternNodes
        |> List.foldr
            (\((Node range _) as patternNode) resultSoFar ->
                mapPattern nameResolver moduleName variables patternNode
                    |> Result.andThen
                        (\( patternVariables, elemPattern ) ->
                            resultSoFar
                                |> Result.andThen
                                    (\( patternVariablesSoFar, elemPatternsSoFar ) ->
                                        let
                                            overlappingVariableNames : Set String
                                            overlappingVariableNames =
                                                Set.intersect patternVariablesSoFar patternVariables
                                        in
                                        if Set.isEmpty overlappingVariableNames then
                                            Ok ( Set.union patternVariablesSoFar patternVariables, elemPattern :: elemPatternsSoFar )

                                        else
                                            Err [ SameNameAppearsMultipleTimesInPattern (SourceLocation moduleName range) overlappingVariableNames ]
                                    )
                        )
            )
            (Ok ( Set.empty, [] ))


mapOperator : Elm.ModuleName -> Range -> String -> Result Errors (Value.Value TypeAttribute ValueAttribute)
mapOperator moduleName range op =
    case op of
        "||" ->
            Ok <| SDKBasics.or defaultValueAttribute

        "&&" ->
            Ok <| SDKBasics.and defaultValueAttribute

        "==" ->
            Ok <| SDKBasics.equal defaultValueAttribute

        "/=" ->
            Ok <| SDKBasics.notEqual defaultValueAttribute

        "<" ->
            Ok <| SDKBasics.lessThan defaultValueAttribute

        ">" ->
            Ok <| SDKBasics.greaterThan defaultValueAttribute

        "<=" ->
            Ok <| SDKBasics.lessThanOrEqual defaultValueAttribute

        ">=" ->
            Ok <| SDKBasics.greaterThanOrEqual defaultValueAttribute

        "++" ->
            Ok <| SDKBasics.append defaultValueAttribute

        "+" ->
            Ok <| SDKBasics.add defaultValueAttribute

        "-" ->
            Ok <| SDKBasics.subtract defaultValueAttribute

        "*" ->
            Ok <| SDKBasics.multiply defaultValueAttribute

        "/" ->
            Ok <| SDKBasics.divide defaultValueAttribute

        "//" ->
            Ok <| SDKBasics.integerDivide defaultValueAttribute

        "^" ->
            Ok <| SDKBasics.power defaultValueAttribute

        "<<" ->
            Ok <| SDKBasics.composeLeft defaultValueAttribute

        ">>" ->
            Ok <| SDKBasics.composeRight defaultValueAttribute

        "::" ->
            Ok <| List.construct defaultValueAttribute

        _ ->
            Err
                [ NotSupported
                    (SourceLocation moduleName range)
                    ("OperatorApplication: " ++ op)
                ]


mapLetExpression : (List String -> String -> KindOfName -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Set String -> Expression.LetBlock -> Result Errors (Value.Value TypeAttribute ValueAttribute)
mapLetExpression nameResolver moduleName variables letBlock =
    let
        namesReferredByExpression : Expression -> List String
        namesReferredByExpression expression =
            case expression of
                Expression.Application argNodes ->
                    argNodes |> List.concatMap (Node.value >> namesReferredByExpression)

                Expression.OperatorApplication _ _ (Node _ leftExp) (Node _ rightExp) ->
                    namesReferredByExpression leftExp ++ namesReferredByExpression rightExp

                Expression.FunctionOrValue [] name ->
                    [ name ]

                Expression.IfBlock (Node _ condExp) (Node _ thenExp) (Node _ elseExp) ->
                    namesReferredByExpression condExp ++ namesReferredByExpression thenExp ++ namesReferredByExpression elseExp

                Expression.Negation (Node _ childExp) ->
                    namesReferredByExpression childExp

                Expression.TupledExpression argNodes ->
                    argNodes |> List.concatMap (Node.value >> namesReferredByExpression)

                Expression.ParenthesizedExpression (Node _ childExp) ->
                    namesReferredByExpression childExp

                Expression.LetExpression innerLetBlock ->
                    innerLetBlock.declarations
                        |> List.concatMap
                            (\(Node _ decl) ->
                                case decl of
                                    Expression.LetFunction function ->
                                        function.declaration |> Node.value |> .expression |> Node.value |> namesReferredByExpression

                                    Expression.LetDestructuring _ (Node _ childExp) ->
                                        namesReferredByExpression childExp
                            )
                        |> (++) (innerLetBlock.expression |> Node.value |> namesReferredByExpression)

                Expression.CaseExpression caseBlock ->
                    caseBlock.cases
                        |> List.concatMap
                            (\( _, Node _ childExp ) ->
                                namesReferredByExpression childExp
                            )
                        |> (++) (caseBlock.expression |> Node.value |> namesReferredByExpression)

                Expression.LambdaExpression lambda ->
                    lambda.expression |> Node.value |> namesReferredByExpression

                Expression.RecordExpr setterNodes ->
                    setterNodes |> List.concatMap (\(Node _ ( _, Node _ childExp )) -> namesReferredByExpression childExp)

                Expression.ListExpr argNodes ->
                    argNodes |> List.concatMap (Node.value >> namesReferredByExpression)

                Expression.RecordAccess (Node _ childExp) _ ->
                    namesReferredByExpression childExp

                Expression.RecordUpdateExpression (Node _ recordRef) setterNodes ->
                    recordRef :: (setterNodes |> List.concatMap (\(Node _ ( _, Node _ childExp )) -> namesReferredByExpression childExp))

                _ ->
                    []

        letBlockToValue : List (Node Expression.LetDeclaration) -> Node Expression -> Result Errors (Value.Value TypeAttribute ValueAttribute)
        letBlockToValue declarationNodes inNode =
            let
                -- build a dictionary from variable name to declaration index
                declarationIndexForName : Dict String Int
                declarationIndexForName =
                    declarationNodes
                        |> List.indexedMap
                            (\index (Node _ decl) ->
                                case decl of
                                    Expression.LetFunction function ->
                                        [ ( function.declaration |> Node.value |> .name |> Node.value, index ) ]

                                    Expression.LetDestructuring (Node _ pattern) _ ->
                                        namesBoundByPattern pattern
                                            |> Set.map (\name -> ( name, index ))
                                            |> Set.toList
                            )
                        |> List.concat
                        |> Dict.fromList

                allVariables : Set String
                allVariables =
                    variables |> Set.union (declarationIndexForName |> Dict.keys |> Set.fromList)

                -- build a dependency graph between declarations
                declarationDependencyGraph : Graph (Node Expression.LetDeclaration) String
                declarationDependencyGraph =
                    let
                        nodes : List (Graph.Node (Node Expression.LetDeclaration))
                        nodes =
                            declarationNodes
                                |> List.indexedMap
                                    (\index declNode ->
                                        Graph.Node index declNode
                                    )

                        edges : List (Graph.Edge String)
                        edges =
                            declarationNodes
                                |> List.indexedMap
                                    (\fromIndex (Node _ decl) ->
                                        case decl of
                                            Expression.LetFunction function ->
                                                function.declaration
                                                    |> Node.value
                                                    |> .expression
                                                    |> Node.value
                                                    |> namesReferredByExpression
                                                    |> List.filterMap
                                                        (\name ->
                                                            declarationIndexForName
                                                                |> Dict.get name
                                                                |> Maybe.map (\toIndex -> Graph.Edge fromIndex toIndex name)
                                                        )

                                            Expression.LetDestructuring _ expression ->
                                                expression
                                                    |> Node.value
                                                    |> namesReferredByExpression
                                                    |> List.filterMap
                                                        (\name ->
                                                            declarationIndexForName
                                                                |> Dict.get name
                                                                |> Maybe.map (\toIndex -> Graph.Edge fromIndex toIndex name)
                                                        )
                                    )
                                |> List.concat
                    in
                    Graph.fromNodesAndEdges nodes edges

                letDeclarationToValue : Node Expression.LetDeclaration -> Result Errors (Value.Value TypeAttribute ValueAttribute) -> Result Errors (Value.Value TypeAttribute ValueAttribute)
                letDeclarationToValue letDeclarationNode valueResult =
                    case letDeclarationNode of
                        Node range (Expression.LetFunction function) ->
                            Result.map2
                                (\bindingDef inValue ->
                                    Value.LetDefinition defaultValueAttribute
                                        (function.declaration |> Node.value |> .name |> Node.value |> Name.fromString)
                                        bindingDef
                                        (inValue |> valueWithDefaultTypeAttribute)
                                )
                                (mapFunction nameResolver moduleName allVariables (Node range function))
                                valueResult

                        Node _ (Expression.LetDestructuring ((Node _ expPattern) as patternNode) letExpressionNode) ->
                            Result.map3
                                (\( patternVariables, bindPattern ) bindValue inValue ->
                                    Value.Destructure defaultValueAttribute
                                        bindPattern
                                        (bindValue |> valueWithDefaultTypeAttribute)
                                        (inValue |> valueWithDefaultTypeAttribute)
                                )
                                (mapPattern nameResolver moduleName (allVariables |> Set.diff (namesBoundByPattern expPattern)) patternNode)
                                (mapExpression nameResolver moduleName allVariables letExpressionNode)
                                valueResult

                componentGraphToValue : Graph (Node Expression.LetDeclaration) String -> Result Errors (Value.Value TypeAttribute ValueAttribute) -> Result Errors (Value.Value TypeAttribute ValueAttribute)
                componentGraphToValue componentGraph inValueResult =
                    case componentGraph |> Graph.checkAcyclic of
                        Ok acyclic ->
                            acyclic
                                |> Graph.topologicalSort
                                |> List.foldl
                                    (\nodeContext innerSoFar ->
                                        letDeclarationToValue nodeContext.node.label innerSoFar
                                    )
                                    (inValueResult |> Result.map valueWithDefaultTypeAttribute)

                        Err _ ->
                            Result.map2 (Value.LetRecursion defaultValueAttribute)
                                (componentGraph
                                    |> Graph.nodes
                                    |> List.map
                                        (\graphNode ->
                                            case graphNode.label of
                                                Node range (Expression.LetFunction function) ->
                                                    mapFunction nameResolver moduleName allVariables (Node range function)
                                                        |> Result.map (Tuple.pair (function.declaration |> Node.value |> .name |> Node.value |> Name.fromString))

                                                Node range (Expression.LetDestructuring _ _) ->
                                                    Err
                                                        [ NotSupported
                                                            (SourceLocation moduleName range)
                                                            "Recursive destructuring"
                                                        ]
                                        )
                                    |> ResultList.keepAllErrors
                                    |> Result.mapError List.concat
                                    |> Result.map Dict.fromList
                                )
                                (inValueResult |> Result.map valueWithDefaultTypeAttribute)
            in
            case declarationDependencyGraph |> Graph.stronglyConnectedComponents of
                Ok acyclic ->
                    acyclic
                        |> Graph.topologicalSort
                        |> List.foldl
                            (\nodeContext soFar ->
                                letDeclarationToValue nodeContext.node.label soFar
                            )
                            (mapExpression nameResolver moduleName allVariables inNode |> Result.map valueWithDefaultTypeAttribute)

                Err components ->
                    components
                        |> List.foldl
                            componentGraphToValue
                            (mapExpression nameResolver moduleName allVariables inNode |> Result.map valueWithDefaultTypeAttribute)
    in
    letBlockToValue letBlock.declarations letBlock.expression


namesBoundByPattern : Pattern -> Set String
namesBoundByPattern p =
    let
        namesBound : Pattern -> List String
        namesBound pattern =
            case pattern of
                Pattern.TuplePattern elemPatternNodes ->
                    elemPatternNodes |> List.concatMap (Node.value >> namesBound)

                Pattern.RecordPattern fieldNameNodes ->
                    fieldNameNodes |> List.map Node.value

                Pattern.UnConsPattern (Node _ headPattern) (Node _ tailPattern) ->
                    namesBound headPattern ++ namesBound tailPattern

                Pattern.ListPattern itemPatternNodes ->
                    itemPatternNodes |> List.concatMap (Node.value >> namesBound)

                Pattern.VarPattern name ->
                    [ name ]

                Pattern.NamedPattern _ argPatternNodes ->
                    argPatternNodes |> List.concatMap (Node.value >> namesBound)

                Pattern.AsPattern (Node _ childPattern) (Node _ alias) ->
                    alias :: namesBound childPattern

                Pattern.ParenthesizedPattern (Node _ childPattern) ->
                    namesBound childPattern

                _ ->
                    []
    in
    namesBound p
        |> Set.fromList


valueWithDefaultTypeAttribute : Value ta va -> Value TypeAttribute va
valueWithDefaultTypeAttribute value =
    value |> Value.mapValueAttributes (always False) identity
