module Morphir.Elm.Frontend.Mapper exposing (Error(..), Errors, SourceLocation, mapDeclarationsToValue, mapFunction, mapTypeAnnotation)

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
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Literal as Literal
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.SDK.Basics as SDKBasics
import Morphir.IR.SDK.List as List
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value
import Morphir.SDK.ResultList as ResultList
import Set exposing (Set)


type alias Errors =
    List Error


type Error
    = EmptyApply SourceLocation
    | NotSupported SourceLocation String
    | RecordPatternNotSupported SourceLocation
      -- TODO figure out where this error needs to be
    | ResolveError IncrementalResolve.Error


type alias SourceLocation =
    { moduleName : ElmModuleName
    , location : Range
    }


type alias Range =
    Range.Range


type alias ElmModuleName =
    ElmModuleName.ModuleName



-- Type Mappings


mapTypeAnnotation : (List String -> String -> Result IncrementalResolve.Error FQName) -> Node TypeAnnotation -> Result Errors (Type ())
mapTypeAnnotation resolveTypeName (Node _ typeAnnotation) =
    case typeAnnotation of
        GenericType varName ->
            Ok (Type.Variable () (varName |> Name.fromString))

        Typed (Node _ ( moduleName, localName )) argNodes ->
            Result.map2
                (Type.Reference ())
                (resolveTypeName moduleName localName |> Result.mapError (ResolveError >> List.singleton))
                (argNodes
                    |> List.map (mapTypeAnnotation resolveTypeName)
                    |> ResultList.keepAllErrors
                    |> Result.mapError List.concat
                )

        Unit ->
            Ok (Type.Unit ())

        Tupled typeAnnotationNodes ->
            typeAnnotationNodes
                |> List.map (mapTypeAnnotation resolveTypeName)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Type.Tuple ())

        Record fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ argName, fieldTypeNode ) ->
                        mapTypeAnnotation resolveTypeName fieldTypeNode
                            |> Result.map (Type.Field (Name.fromString argName))
                    )
                |> ResultList.keepAllErrors
                |> Result.map (Type.Record ())
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
                |> Result.map (Type.ExtensibleRecord () (Name.fromString argName))
                |> Result.mapError List.concat

        FunctionTypeAnnotation argTypeNode returnTypeNode ->
            Result.map2
                (Type.Function ())
                (mapTypeAnnotation resolveTypeName argTypeNode)
                (mapTypeAnnotation resolveTypeName returnTypeNode)



-- Value Mappings


mapDeclarationsToValue : (List String -> String -> Result IncrementalResolve.Error FQName) -> ParsedModule -> List (Node Declaration) -> Result Errors (List ( FQName, Value.Definition () (Type ()) ))
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
                                    |> resolveName moduleName
                                    |> Result.mapError (ResolveError >> List.singleton)

                            valueDef : Result Errors (Value.Definition () (Type ()))
                            valueDef =
                                Node range function
                                    |> mapFunction resolveName moduleName
                        in
                        valueDef
                            |> Result.map2 Tuple.pair valueName
                            |> Just

                    _ ->
                        Nothing
            )
        |> ResultList.keepAllErrors
        |> Result.mapError List.concat


mapExpression : (List String -> String -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Node Expression -> Result Errors (Value.Value () (Type ()))
mapExpression resolveReferenceName moduleName (Node range expr) =
    case expr of
        Expression.UnitExpr ->
            Value.Unit (Type.Unit ()) |> Ok

        Expression.Application expNodes ->
            let
                toApply : List (Value.Value () (Type ())) -> Result Errors (Value.Value () (Type ()))
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
                                        Value.Apply (Type.Unit ()) funValue lastValue
                                    )
            in
            expNodes
                |> List.map (mapExpression resolveReferenceName moduleName)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.andThen (List.reverse >> toApply)

        Expression.OperatorApplication op _ leftNode rightNode ->
            case op of
                "<|" ->
                    -- the purpose of this operator is cleaner syntax so it's not mapped to the IR
                    Result.map2 (Value.Apply (Type.Unit ()))
                        (mapExpression resolveReferenceName moduleName leftNode)
                        (mapExpression resolveReferenceName moduleName rightNode)

                "|>" ->
                    -- the purpose of this operator is cleaner syntax so it's not mapped to the IR
                    Result.map2
                        (Value.Apply (Type.Unit ()))
                        (mapExpression resolveReferenceName moduleName rightNode)
                        (mapExpression resolveReferenceName moduleName leftNode)

                _ ->
                    Result.map3 (\fun arg1 arg2 -> Value.Apply (Type.Unit ()) (Value.Apply (Type.Unit ()) fun arg1) arg2)
                        (mapOperator moduleName range op)
                        (mapExpression resolveReferenceName moduleName leftNode)
                        (mapExpression resolveReferenceName moduleName rightNode)

        Expression.FunctionOrValue modName localName ->
            localName
                |> String.uncons
                |> Result.fromMaybe [ NotSupported (SourceLocation moduleName range) "Empty value name" ]
                |> Result.andThen
                    (\( firstChar, _ ) ->
                        if Char.isUpper firstChar then
                            case ( modName, localName ) of
                                ( [], "True" ) ->
                                    Ok (Value.Literal (Type.Unit ()) (Literal.BoolLiteral True))

                                ( [], "False" ) ->
                                    Ok (Value.Literal (Type.Unit ()) (Literal.BoolLiteral False))

                                _ ->
                                    resolveReferenceName modName localName
                                        |> Result.mapError (ResolveError >> List.singleton)
                                        |> Result.map (Value.Constructor (Type.Unit ()))

                        else
                            resolveReferenceName modName localName
                                |> Result.mapError (ResolveError >> List.singleton)
                                |> Result.map (Value.Reference (Type.Unit ()))
                    )

        Expression.IfBlock condNode thenNode elseNode ->
            Result.map3 (Value.IfThenElse (Type.Unit ()))
                (mapExpression resolveReferenceName moduleName condNode)
                (mapExpression resolveReferenceName moduleName thenNode)
                (mapExpression resolveReferenceName moduleName elseNode)

        Expression.PrefixOperator op ->
            mapOperator moduleName range op

        Expression.Operator op ->
            mapOperator moduleName range op

        Expression.Integer value ->
            Ok (Value.Literal (Type.Unit ()) (Literal.WholeNumberLiteral value))

        Expression.Hex value ->
            Ok (Value.Literal (Type.Unit ()) (Literal.WholeNumberLiteral value))

        Expression.Floatable value ->
            Ok (Value.Literal (Type.Unit ()) (Literal.FloatLiteral value))

        Expression.Negation arg ->
            mapExpression resolveReferenceName moduleName arg
                |> Result.map (SDKBasics.negate (Type.Unit ()) (Type.Unit ()))

        Expression.Literal value ->
            Ok (Value.Literal (Type.Unit ()) (Literal.StringLiteral value))

        Expression.CharLiteral value ->
            Ok (Value.Literal (Type.Unit ()) (Literal.CharLiteral value))

        Expression.TupledExpression expNodes ->
            expNodes
                |> List.map (mapExpression resolveReferenceName moduleName)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.Tuple (Type.Unit ()))

        Expression.ParenthesizedExpression expNode ->
            mapExpression resolveReferenceName moduleName expNode

        Expression.LetExpression letBlock ->
            mapLetExpression
                resolveReferenceName
                moduleName
                letBlock

        Expression.CaseExpression caseBlock ->
            Result.map2 (Value.PatternMatch (Type.Unit ()))
                (mapExpression resolveReferenceName moduleName caseBlock.expression)
                (caseBlock.cases
                    |> List.map
                        (\( patternNode, bodyNode ) ->
                            Result.map2 Tuple.pair
                                (mapPattern resolveReferenceName moduleName patternNode)
                                (mapExpression resolveReferenceName moduleName bodyNode)
                        )
                    |> ResultList.keepAllErrors
                    |> Result.mapError List.concat
                )

        Expression.LambdaExpression lambda ->
            let
                curriedLambda : List (Node Pattern) -> Node Expression -> Result Errors (Value.Value () (Type ()))
                curriedLambda argNodes bodyNode =
                    case argNodes of
                        [] ->
                            mapExpression resolveReferenceName moduleName bodyNode

                        firstArgNode :: restOfArgNodes ->
                            Result.map2 (Value.Lambda (Type.Unit ()))
                                (mapPattern resolveReferenceName moduleName firstArgNode)
                                (curriedLambda restOfArgNodes bodyNode)
            in
            curriedLambda lambda.args lambda.expression

        Expression.RecordExpr fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldValue ) ->
                        mapExpression resolveReferenceName moduleName fieldValue
                            |> Result.map (Tuple.pair (fieldName |> Name.fromString))
                    )
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.Record (Type.Unit ()))

        Expression.ListExpr itemNodes ->
            itemNodes
                |> List.map (mapExpression resolveReferenceName moduleName)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.List (Type.Unit ()))

        Expression.RecordAccess targetNode fieldNameNode ->
            mapExpression resolveReferenceName moduleName targetNode
                |> Result.map
                    (\subjectValue ->
                        Value.Field (Type.Unit ())
                            subjectValue
                            (fieldNameNode |> Node.value |> Name.fromString)
                    )

        Expression.RecordAccessFunction fieldName ->
            Ok (Value.FieldFunction (Type.Unit ()) (fieldName |> Name.fromString))

        Expression.RecordUpdateExpression targetVarNameNode fieldNodes ->
            fieldNodes
                |> List.map Node.value
                |> List.map
                    (\( Node _ fieldName, fieldValue ) ->
                        mapExpression resolveReferenceName moduleName fieldValue
                            |> Result.map (Tuple.pair (fieldName |> Name.fromString))
                    )
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map
                    (Value.UpdateRecord
                        (Type.Unit ())
                        (targetVarNameNode |> Node.value |> Name.fromString |> Value.Variable (Type.Unit ()))
                    )

        Expression.GLSLExpression _ ->
            Err
                [ NotSupported
                    (SourceLocation moduleName range)
                    "GLSLExpression"
                ]


mapFunction : (List String -> String -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Node Expression.Function -> Result Errors (Value.Definition () (Type ()))
mapFunction resolveName moduleName (Node functionRange function) =
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
    in
    mapExpression resolveName moduleName expression
        |> Result.map (Value.Definition [] (Type.Unit ()))
        |> Result.map liftLambdaArguments


{-| Moves lambda arguments into function arguments as much as possible. For example given this function definition:

    foo : Int -> Bool -> ( Int, Int ) -> String
    foo =
        \a ->
            \b ->
                ( c, d ) ->
                    doSomething a b c d

It turns it into the following:

    foo : Int -> Bool -> ( Int, Int ) -> String
    foo a b =
        ( c, d ) ->
            doSomething a b c d

-}
liftLambdaArguments : Value.Definition ta va -> Value.Definition ta va
liftLambdaArguments valueDef =
    case ( valueDef.body, valueDef.outputType ) of
        ( Value.Lambda va (Value.AsPattern _ (Value.WildcardPattern _) argName) lambdaBody, Type.Function _ argType returnType ) ->
            liftLambdaArguments
                { inputTypes = valueDef.inputTypes ++ [ ( argName, va, argType ) ]
                , outputType = returnType
                , body = lambdaBody
                }

        _ ->
            valueDef


mapPattern : (List String -> String -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Node Pattern -> Result Errors (Value.Pattern (Type ()))
mapPattern nameResolver moduleName (Node range pattern) =
    case pattern of
        Pattern.AllPattern ->
            Ok (Value.WildcardPattern (Type.Unit ()))

        Pattern.UnitPattern ->
            Ok (Value.UnitPattern (Type.Unit ()))

        Pattern.CharPattern char ->
            Ok (Value.LiteralPattern (Type.Unit ()) (Literal.CharLiteral char))

        Pattern.StringPattern string ->
            Ok (Value.LiteralPattern (Type.Unit ()) (Literal.StringLiteral string))

        Pattern.IntPattern int ->
            Ok (Value.LiteralPattern (Type.Unit ()) (Literal.WholeNumberLiteral int))

        Pattern.HexPattern int ->
            Ok (Value.LiteralPattern (Type.Unit ()) (Literal.WholeNumberLiteral int))

        Pattern.FloatPattern float ->
            Ok (Value.LiteralPattern (Type.Unit ()) (Literal.FloatLiteral float))

        Pattern.TuplePattern elemNodes ->
            elemNodes
                |> List.map (mapPattern nameResolver moduleName)
                |> ResultList.keepAllErrors
                |> Result.mapError List.concat
                |> Result.map (Value.TuplePattern (Type.Unit ()))

        Pattern.RecordPattern _ ->
            Err
                [ SourceLocation moduleName range
                    |> RecordPatternNotSupported
                ]

        Pattern.UnConsPattern headNode tailNode ->
            Result.map2 (Value.HeadTailPattern (Type.Unit ()))
                (mapPattern nameResolver moduleName headNode)
                (mapPattern nameResolver moduleName tailNode)

        Pattern.ListPattern itemNodes ->
            let
                toPattern : List (Node Pattern) -> Result Errors (Value.Pattern (Type ()))
                toPattern patternNodes =
                    case patternNodes of
                        [] ->
                            Ok (Value.EmptyListPattern (Type.Unit ()))

                        headNode :: tailNodes ->
                            Result.map2 (Value.HeadTailPattern (Type.Unit ()))
                                (mapPattern nameResolver moduleName headNode)
                                (toPattern tailNodes)
            in
            toPattern itemNodes

        Pattern.VarPattern name ->
            Ok (Value.AsPattern (Type.Unit ()) (Value.WildcardPattern (Type.Unit ())) (Name.fromString name))

        Pattern.NamedPattern qualifiedNameRef argNodes ->
            let
                fullyQualifiedName : Result Errors FQName
                fullyQualifiedName =
                    nameResolver qualifiedNameRef.moduleName qualifiedNameRef.name
                        |> Result.mapError (ResolveError >> List.singleton)
            in
            case ( qualifiedNameRef.moduleName, qualifiedNameRef.name ) of
                ( [], "True" ) ->
                    Ok (Value.LiteralPattern (Type.Unit ()) (Literal.BoolLiteral True))

                ( [], "False" ) ->
                    Ok (Value.LiteralPattern (Type.Unit ()) (Literal.BoolLiteral False))

                _ ->
                    argNodes
                        |> List.map (mapPattern nameResolver moduleName)
                        |> ResultList.keepAllErrors
                        |> Result.mapError List.concat
                        |> Result.map2
                            (Value.ConstructorPattern (Type.Unit ()))
                            fullyQualifiedName

        Pattern.AsPattern subjectNode aliasNode ->
            mapPattern nameResolver moduleName subjectNode
                |> Result.map
                    (\subject ->
                        Value.AsPattern (Type.Unit ())
                            subject
                            (aliasNode |> Node.value |> Name.fromString)
                    )

        Pattern.ParenthesizedPattern childNode ->
            mapPattern nameResolver moduleName childNode


mapOperator : Elm.ModuleName -> Range -> String -> Result Errors (Value.Value () (Type ()))
mapOperator moduleName range op =
    case op of
        "||" ->
            Ok <| SDKBasics.or (Type.Unit ())

        "&&" ->
            Ok <| SDKBasics.and (Type.Unit ())

        "==" ->
            Ok <| SDKBasics.equal (Type.Unit ())

        "/=" ->
            Ok <| SDKBasics.notEqual (Type.Unit ())

        "<" ->
            Ok <| SDKBasics.lessThan (Type.Unit ())

        ">" ->
            Ok <| SDKBasics.greaterThan (Type.Unit ())

        "<=" ->
            Ok <| SDKBasics.lessThanOrEqual (Type.Unit ())

        ">=" ->
            Ok <| SDKBasics.greaterThanOrEqual (Type.Unit ())

        "++" ->
            Err
                [ NotSupported
                    (SourceLocation moduleName range)
                    "The ++ operator is currently not supported. Please use String.append or List.append. See docs/error-append-not-supported.md"
                ]

        "+" ->
            Ok <| SDKBasics.add (Type.Unit ())

        "-" ->
            Ok <| SDKBasics.subtract (Type.Unit ())

        "*" ->
            Ok <| SDKBasics.multiply (Type.Unit ())

        "/" ->
            Ok <| SDKBasics.divide (Type.Unit ())

        "//" ->
            Ok <| SDKBasics.integerDivide (Type.Unit ())

        "^" ->
            Ok <| SDKBasics.power (Type.Unit ())

        "<<" ->
            Ok <| SDKBasics.composeLeft (Type.Unit ())

        ">>" ->
            Ok <| SDKBasics.composeRight (Type.Unit ())

        "::" ->
            Ok <| List.construct (Type.Unit ())

        _ ->
            Err
                [ NotSupported
                    (SourceLocation moduleName range)
                    ("OperatorApplication: " ++ op)
                ]


mapLetExpression : (List String -> String -> Result IncrementalResolve.Error FQName) -> Elm.ModuleName -> Expression.LetBlock -> Result Errors (Value.Value () (Type ()))
mapLetExpression nameResolver moduleName letBlock =
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

        letBlockToValue : List (Node Expression.LetDeclaration) -> Node Expression -> Result Errors (Value.Value () (Type ()))
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

                letDeclarationToValue : Node Expression.LetDeclaration -> Result Errors (Value.Value () (Type ())) -> Result Errors (Value.Value () (Type ()))
                letDeclarationToValue letDeclarationNode valueResult =
                    case letDeclarationNode of
                        Node range (Expression.LetFunction function) ->
                            Result.map2 (Value.LetDefinition (Type.Unit ()) (function.declaration |> Node.value |> .name |> Node.value |> Name.fromString))
                                (mapFunction nameResolver moduleName (Node range function))
                                valueResult

                        Node _ (Expression.LetDestructuring patternNode letExpressionNode) ->
                            Result.map3 (Value.Destructure (Type.Unit ()))
                                (mapPattern nameResolver moduleName patternNode)
                                (mapExpression nameResolver moduleName letExpressionNode)
                                valueResult

                componentGraphToValue : Graph (Node Expression.LetDeclaration) String -> Result Errors (Value.Value () (Type ())) -> Result Errors (Value.Value () (Type ()))
                componentGraphToValue componentGraph valueResult =
                    case componentGraph |> Graph.checkAcyclic of
                        Ok acyclic ->
                            acyclic
                                |> Graph.topologicalSort
                                |> List.foldl
                                    (\nodeContext innerSoFar ->
                                        letDeclarationToValue nodeContext.node.label innerSoFar
                                    )
                                    valueResult

                        Err _ ->
                            Result.map2 (Value.LetRecursion (Type.Unit ()))
                                (componentGraph
                                    |> Graph.nodes
                                    |> List.map
                                        (\graphNode ->
                                            case graphNode.label of
                                                Node range (Expression.LetFunction function) ->
                                                    mapFunction nameResolver moduleName (Node range function)
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
                                valueResult
            in
            case declarationDependencyGraph |> Graph.stronglyConnectedComponents of
                Ok acyclic ->
                    acyclic
                        |> Graph.topologicalSort
                        |> List.foldl
                            (\nodeContext soFar ->
                                letDeclarationToValue nodeContext.node.label soFar
                            )
                            (mapExpression nameResolver moduleName inNode)

                Err components ->
                    components
                        |> List.foldl
                            componentGraphToValue
                            (mapExpression nameResolver moduleName inNode)
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
