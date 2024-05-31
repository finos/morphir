module Morphir.TypeScript.Backend.Types exposing (mapPrivacy, mapTypeDefinition)

{-| This module contains the TypeScript backend that translates the Morphir IR Types
into TypeScript.
-}

import Dict
import Maybe exposing (withDefault)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.TypeScript.AST as TS
import Set exposing (Set)


type alias TypeVariablesList =
    List Name


type alias ConstructorDetail a =
    { name : Name
    , privacy : TS.Privacy
    , args : List ( Name, Type a )
    , typeVariables : List (Type a)
    , typeVariableNames : List Name
    }


inputIndexArg : Int -> TS.Expression
inputIndexArg index =
    TS.IndexedExpression
        { object = TS.Identifier "input"
        , index = TS.IntLiteralExpression index
        }


prependDecodeToName : Name -> String
prependDecodeToName name =
    ("decode" :: name) |> Name.toCamelCase


prependEncodeToName : Name -> String
prependEncodeToName name =
    ("encode" :: name) |> Name.toCamelCase


getConstructorDetails : TS.Privacy -> ( Name, List ( Name, Type a ) ) -> ConstructorDetail a
getConstructorDetails privacy ( ctorName, ctorArgs ) =
    let
        typeVariables : List (Type a)
        typeVariables =
            ctorArgs
                |> List.map Tuple.second
                |> List.concatMap collectTypeVariables
                |> deduplicateTypeVariables
    in
    { name = ctorName
    , privacy = privacy
    , args = ctorArgs
    , typeVariables = typeVariables
    , typeVariableNames =
        typeVariables
            |> List.map
                (\argType ->
                    case argType of
                        Type.Variable _ name ->
                            name

                        _ ->
                            -- Should never happen
                            []
                )
    }


collectTypeVariables : Type.Type a -> List (Type.Type a)
collectTypeVariables typeExp =
    case typeExp of
        Type.Variable _ _ ->
            [ typeExp ]

        Type.Reference _ _ argTypes ->
            argTypes |> List.concatMap collectTypeVariables

        Type.Tuple _ valueTypes ->
            valueTypes |> List.concatMap collectTypeVariables

        Type.Record _ fieldTypes ->
            fieldTypes |> List.concatMap (\field -> field.tpe |> collectTypeVariables)

        Type.ExtensibleRecord _ _ fieldTypes ->
            fieldTypes |> List.concatMap (\field -> field.tpe |> collectTypeVariables)

        Type.Function _ argumentType returnType ->
            [ argumentType, returnType ] |> List.concatMap collectTypeVariables

        Type.Unit _ ->
            []


type alias TypeList a =
    List (Type.Type a)


deduplicateTypeVariables : TypeList a -> TypeList a
deduplicateTypeVariables list =
    let
        compareAndReturn : Set String -> TypeList a -> TypeList a -> TypeList a
        compareAndReturn seen remaining result =
            case remaining of
                [] ->
                    result

                item :: rest ->
                    case item of
                        Type.Variable _ name ->
                            if Set.member (Name.toTitleCase name) seen then
                                compareAndReturn seen rest result

                            else
                                item
                                    :: compareAndReturn
                                        (Set.insert (Name.toTitleCase name) seen)
                                        remaining
                                        result

                        _ ->
                            []
    in
    compareAndReturn Set.empty list []


{-| Map a Morphir type definition into a list of TypeScript type definitions. The reason for returning a list is that
some Morphir type definitions can only be represented by a combination of multiple type definitions in TypeScript.
-}
mapTypeDefinition : Name -> AccessControlled (Documented (Type.Definition ta)) -> List TS.TypeDef
mapTypeDefinition name typeDef =
    let
        doc =
            typeDef.value.doc

        privacy =
            typeDef.access |> mapPrivacy
    in
    case typeDef.value.value of
        Type.TypeAliasDefinition variables typeExp ->
            [ TS.TypeAlias
                { name = name |> Name.toTitleCase
                , privacy = privacy
                , doc = doc
                , variables = variables |> List.map Name.toTitleCase |> List.map (\var -> TS.Variable var)
                , typeExpression = typeExp |> mapTypeExp
                , decoder = Just (generateDecoderFunction variables name typeDef.access typeExp)
                , encoder = Just (generateEncoderFunction variables name typeDef.access typeExp)
                }
            ]

        Type.CustomTypeDefinition variables accessControlledConstructors ->
            let
                constructorDetails : List (ConstructorDetail ta)
                constructorDetails =
                    accessControlledConstructors.value
                        |> Dict.toList
                        |> List.map (getConstructorDetails privacy)

                constructorInterfaces =
                    constructorDetails
                        |> List.map mapConstructor

                tsVariables : List TS.TypeExp
                tsVariables =
                    variables |> List.map (Name.toTitleCase >> TS.Variable)

                constructorNames =
                    accessControlledConstructors.value
                        |> Dict.keys

                unionExpressionFromConstructorDetails : List (ConstructorDetail a) -> TS.TypeExp
                unionExpressionFromConstructorDetails constructors =
                    TS.Union
                        (constructors
                            |> List.map
                                (\constructor ->
                                    TS.TypeRef
                                        (FQName.fQName [] [] constructor.name)
                                        (constructor.typeVariableNames |> List.map (Name.toTitleCase >> TS.Variable))
                                )
                        )

                union =
                    if List.all ((==) name) constructorNames then
                        []

                    else
                        List.singleton
                            (TS.TypeAlias
                                { name = name |> Name.toTitleCase
                                , privacy = privacy
                                , doc = doc
                                , variables = tsVariables
                                , typeExpression = unionExpressionFromConstructorDetails constructorDetails
                                , decoder = Just (generateUnionDecoderFunction name privacy variables constructorDetails)
                                , encoder = Just (generateUnionEncoderFunction name privacy variables constructorDetails)
                                }
                            )
            in
            union ++ constructorInterfaces


mapPrivacy : Access -> TS.Privacy
mapPrivacy privacy =
    case privacy of
        Public ->
            TS.Public

        Private ->
            TS.Private


{-| Map a Morphir Constructor (A tuple of Name and Constructor Args) to a Typescript AST Interface
-}
mapConstructor : ConstructorDetail ta -> TS.TypeDef
mapConstructor constructor =
    let
        assignKind : TS.Statement
        assignKind =
            TS.AssignmentStatement
                (TS.Identifier "kind")
                (Just (TS.LiteralString (constructor.name |> Name.toTitleCase)))
                (TS.StringLiteralExpression (constructor.name |> Name.toTitleCase))

        typeExpressions : List TS.TypeExp
        typeExpressions =
            constructor.args
                |> List.map (Tuple.second >> mapTypeExp)
    in
    TS.VariantClass
        { name = constructor.name |> Name.toTitleCase
        , privacy = constructor.privacy
        , variables = constructor.typeVariableNames |> List.map (Name.toTitleCase >> TS.Variable)
        , body = [ assignKind ]
        , constructor = Just (generateConstructorConstructorFunction constructor)
        , decoder = Just (generateConstructorDecoderFunction constructor)
        , encoder = Just (generateConstructorEncoderFunction constructor)
        , typeExpressions = typeExpressions
        }


{-| Map a Morphir type expression into a TypeScript type expression.
-}
mapTypeExp : Type.Type ta -> TS.TypeExp
mapTypeExp tpe =
    case tpe of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] ->
            TS.Boolean

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            TS.Number

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            TS.Number
        
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "decimal" ] ], [ "decimal" ] ) [] ->
            TS.Number

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "char" ] ], [ "char" ] ) [] ->
            TS.String

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            TS.String

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ itemType ] ->
            TS.Nullable (mapTypeExp itemType)

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "dict" ] ) [ dictKeyType, dictValType ] ->
            TS.Map (mapTypeExp dictKeyType) (mapTypeExp dictValType)

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ listType ] ->
            TS.List (mapTypeExp listType)

        Type.Record _ fieldList ->
            TS.Object
                (fieldList
                    |> List.map
                        (\field ->
                            ( field.name |> Name.toCamelCase, mapTypeExp field.tpe )
                        )
                )

        Type.Tuple _ tupleTypesList ->
            TS.Tuple (List.map mapTypeExp tupleTypesList)

        Type.Reference _ fQName typeList ->
            TS.TypeRef fQName (typeList |> List.map mapTypeExp)

        Type.Unit _ ->
            TS.Tuple []

        Type.Variable _ name ->
            TS.Variable (Name.toTitleCase name)

        Type.ExtensibleRecord _ _ _ ->
            TS.UnhandledType "ExtensibleRecord"

        Type.Function _ _ _ ->
            TS.UnhandledType "Function"


decoderTypeSignature : TS.TypeExp -> TS.TypeExp
decoderTypeSignature typeExp =
    TS.FunctionTypeExp
        [ TS.Parameter [] "input" (Just TS.Any) ]
        typeExp


encoderTypeSignature : TS.TypeExp -> TS.TypeExp
encoderTypeSignature typeExp =
    TS.FunctionTypeExp
        [ TS.Parameter [] "value" (Just typeExp) ]
        TS.Any


{-| Reference a symbol in the Morphir.Internal.Codecs module.
-}
codecsModule : String -> TS.Expression
codecsModule function =
    TS.MemberExpression
        { object = TS.Identifier "codecs"
        , member = TS.Identifier function
        }


referenceCodec : FQName -> String -> TS.Expression
referenceCodec ( packageName, moduleName, _ ) codecName =
    TS.MemberExpression
        { object = TS.Identifier (TS.namespaceNameFromPackageAndModule packageName moduleName)
        , member = TS.Identifier codecName
        }


buildCodecMap : TS.Expression -> TS.Expression
buildCodecMap array =
    TS.Call
        { function = codecsModule "buildCodecMap"
        , arguments = [ array ]
        }


decoderExpression : TypeVariablesList -> Type.Type a -> TS.Expression -> TS.CallExpression
decoderExpression customTypeVars typeExp inputArg =
    case typeExp of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] ->
            { function = codecsModule "decodeBoolean", arguments = [ inputArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            { function = codecsModule "decodeFloat", arguments = [ inputArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            { function = codecsModule "decodeInt", arguments = [ inputArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "char" ] ], [ "char" ] ) [] ->
            { function = codecsModule "decodeChar", arguments = [ inputArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            { function = codecsModule "decodeString", arguments = [ inputArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ itemType ] ->
            { function = codecsModule "decodeMaybe"
            , arguments =
                [ specificDecoderForType customTypeVars itemType
                , inputArg
                ]
            }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "dict" ] ) [ dictKeyType, dictValType ] ->
            { function = codecsModule "decodeDict"
            , arguments =
                {--decodeKey --}
                [ specificDecoderForType customTypeVars dictKeyType

                {--decodeValue --}
                , specificDecoderForType customTypeVars dictValType
                , inputArg
                ]
            }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ listType ] ->
            { function = codecsModule "decodeList"
            , arguments =
                [ specificDecoderForType customTypeVars listType
                , inputArg
                ]
            }

        Type.Record _ fieldList ->
            { function = codecsModule "decodeRecord"
            , arguments =
                {--fieldDecoders --}
                [ (fieldList
                    |> List.map
                        (\field ->
                            TS.ArrayLiteralExpression
                                [ TS.StringLiteralExpression (Name.toCamelCase field.name)
                                , specificDecoderForType customTypeVars field.tpe
                                ]
                        )
                  )
                    |> TS.ArrayLiteralExpression
                    |> buildCodecMap
                , inputArg
                ]
            }

        Type.Tuple _ tupleTypesList ->
            { function = codecsModule "decodeTuple"
            , arguments =
                {--elementDecoders --}
                [ TS.ArrayLiteralExpression
                    (List.map (specificDecoderForType customTypeVars) tupleTypesList)
                , inputArg
                ]
            }

        Type.Variable _ varName ->
            { function =
                TS.Identifier (prependDecodeToName varName)
            , arguments = [ inputArg ]
            }

        Type.Reference _ fQName argTypes ->
            let
                decoderName =
                    prependDecodeToName (FQName.getLocalName fQName)

                varDecoders =
                    argTypes |> List.map (specificDecoderForType customTypeVars)
            in
            { function = referenceCodec fQName decoderName
            , arguments = varDecoders ++ [ inputArg ]
            }

        Type.Unit _ ->
            { function = codecsModule "decodeUnit"
            , arguments = [ inputArg ]
            }

        {--Unhandled types are treated as Unit --}
        _ ->
            { function = codecsModule "decodeUnit"
            , arguments = [ inputArg ]
            }


bindArgumentsToFunction : TS.Expression -> List TS.Expression -> TS.Expression
bindArgumentsToFunction function args =
    if List.isEmpty args then
        function

    else
        TS.Call
            { function =
                TS.MemberExpression
                    { object = function
                    , member = TS.Identifier "bind"
                    }
            , arguments = TS.NullLiteral :: args
            }


specificDecoderForType : TypeVariablesList -> Type.Type ta -> TS.Expression
specificDecoderForType customTypeVars typeExp =
    let
        expression =
            decoderExpression customTypeVars typeExp (TS.Identifier "input")

        removeInputArg arguments =
            arguments |> List.take (List.length arguments - 1)
    in
    bindArgumentsToFunction expression.function (removeInputArg expression.arguments)


generateDecoderFunction : TypeVariablesList -> Name -> Access -> Type.Type ta -> TS.Statement
generateDecoderFunction variables typeName access typeExp =
    let
        variableTypeExpressions : List TS.TypeExp
        variableTypeExpressions =
            variables |> List.map Name.toTitleCase |> List.map (\var -> TS.Variable var)

        call : TS.CallExpression
        call =
            decoderExpression variables typeExp (TS.Identifier "input")

        variableParams : List TS.Parameter
        variableParams =
            variables
                |> List.map
                    (\var ->
                        TS.parameter
                            []
                            (prependDecodeToName var)
                            (Just (decoderTypeSignature (TS.Variable (Name.toTitleCase var))))
                    )

        inputParam : TS.Parameter
        inputParam =
            TS.parameter [] "input" (Just TS.Any)
    in
    TS.FunctionDeclaration
        { name = prependDecodeToName typeName
        , typeVariables = variableTypeExpressions
        , returnType = Just (TS.TypeRef ( [], [], typeName ) variableTypeExpressions)
        , scope = TS.ModuleFunction
        , parameters = variableParams ++ [ inputParam ]
        , privacy = access |> mapPrivacy
        , body = [ TS.ReturnStatement (TS.Call call) ]
        }


generateConstructorDecoderFunction : ConstructorDetail ta -> TS.Statement
generateConstructorDecoderFunction constructor =
    let
        variableTypeExpressions : List TS.TypeExp
        variableTypeExpressions =
            constructor.typeVariableNames |> List.map Name.toTitleCase |> List.map (\var -> TS.Variable var)

        decoderParams : List TS.Parameter
        decoderParams =
            constructor.typeVariableNames
                |> List.map
                    (\var ->
                        TS.parameter
                            []
                            (prependDecodeToName var)
                            (Just (decoderTypeSignature (TS.Variable (Name.toTitleCase var))))
                    )

        inputParam : TS.Parameter
        inputParam =
            TS.parameter [] "input" (Just TS.Any)

        kind =
            TS.StringLiteralExpression (constructor.name |> Name.toTitleCase)

        validateCall : TS.Expression
        validateCall =
            TS.Call
                { function = codecsModule "preprocessCustomTypeVariant"
                , arguments =
                    [ kind
                    , constructor.args |> List.length |> TS.IntLiteralExpression
                    , TS.Identifier "input"
                    ]
                }

        {--Given an array of inputs (eg  ["PetTrio", "Dalmatian", "Tabby", "Angora"] )
           and a list of constructor argument names and types (eg [("arg1", DogType), ("arg2", CatType), ("arg3", RabbitType)] )
           argDecoderCalls will generate a list of typescript function calls, to decode each of the arguments
           eg [ decodeDog("Dalmatian"), decodeCat("Tabby"), decodeRabbit("Angora") ]
           This generates a list of decoded elements.
-}
        argDecoderCalls : List TS.Expression
        argDecoderCalls =
            constructor.args
                |> List.map Tuple.second
                |> List.indexedMap
                    (\index ->
                        \typExp ->
                            TS.Call
                                (decoderExpression
                                    constructor.typeVariableNames
                                    typExp
                                    (inputIndexArg (index + 1))
                                )
                    )

        {--newCall takes the list of decoded elements (as created by argDecoderCalls)
           and passes it as an argument to a TypeScript class constructor
           ( eg `new PetTrio()` )
-}
        newCall : TS.Expression
        newCall =
            TS.NewExpression
                { constructor = constructor.name |> Name.toTitleCase
                , arguments = argDecoderCalls
                }
    in
    TS.FunctionDeclaration
        { name = prependDecodeToName constructor.name
        , typeVariables = variableTypeExpressions
        , returnType = Just (TS.TypeRef ( [], [], constructor.name ) variableTypeExpressions)
        , scope = TS.ModuleFunction
        , privacy = constructor.privacy
        , parameters = decoderParams ++ [ inputParam ]
        , body =
            [ TS.ExpressionStatement validateCall
            , TS.ReturnStatement newCall
            ]
        }


generateUnionDecoderFunction : Name -> TS.Privacy -> List Name -> List (ConstructorDetail ta) -> TS.Statement
generateUnionDecoderFunction typeName privacy typeVariables constructors =
    let
        variableTypeExpressions : List TS.TypeExp
        variableTypeExpressions =
            typeVariables |> List.map Name.toTitleCase |> List.map (\var -> TS.Variable var)

        decoderParams : List TS.Parameter
        decoderParams =
            typeVariables
                |> List.map
                    (\var ->
                        TS.parameter
                            []
                            (prependDecodeToName var)
                            (Just (decoderTypeSignature (TS.Variable (Name.toTitleCase var))))
                    )

        inputParam : TS.Parameter
        inputParam =
            TS.parameter [] "input" (Just TS.Any)

        kindCall : TS.Statement
        kindCall =
            TS.LetStatement
                (TS.Identifier "kind")
                Nothing
                (TS.Call
                    { function = codecsModule "parseKindFromCustomTypeInput"
                    , arguments = [ TS.Identifier "input" ]
                    }
                )

        errorCall : TS.Statement
        errorCall =
            (TS.Call >> TS.ExpressionStatement)
                { function = codecsModule "raiseDecodeErrorFromCustomType"
                , arguments =
                    [ TS.StringLiteralExpression (typeName |> Name.toTitleCase)
                    , TS.Identifier "kind"
                    ]
                }

        constructorToCaseBlock : ConstructorDetail ta -> ( TS.Expression, List TS.Statement )
        constructorToCaseBlock constructor =
            ( constructor.name |> Name.toTitleCase |> TS.StringLiteralExpression
            , [ TS.ReturnStatement
                    (TS.Call
                        { function = constructor.name |> prependDecodeToName |> TS.Identifier
                        , arguments = (constructor.typeVariableNames |> List.map (prependDecodeToName >> TS.Identifier)) ++ [ TS.Identifier "input" ]
                        }
                    )
              ]
            )

        switchStatement : TS.Statement
        switchStatement =
            TS.SwitchStatement
                (TS.Identifier "kind")
                (constructors |> List.map constructorToCaseBlock)
    in
    TS.FunctionDeclaration
        { name = prependDecodeToName typeName
        , typeVariables = variableTypeExpressions
        , returnType = Just (TS.TypeRef ( [], [], typeName ) variableTypeExpressions)
        , scope = TS.ModuleFunction
        , privacy = privacy
        , parameters = decoderParams ++ [ inputParam ]
        , body = [ kindCall, switchStatement, errorCall ]
        }


encoderExpression : TypeVariablesList -> Type.Type a -> TS.Expression -> TS.CallExpression
encoderExpression customTypeVars typeExp valueArg =
    case typeExp of
        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) [] ->
            { function = codecsModule "encodeBoolean", arguments = [ valueArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) [] ->
            { function = codecsModule "encodeFloat", arguments = [ valueArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) [] ->
            { function = codecsModule "encodeInt", arguments = [ valueArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "char" ] ], [ "char" ] ) [] ->
            { function = codecsModule "encodeChar", arguments = [ valueArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) [] ->
            { function = codecsModule "encodeString", arguments = [ valueArg ] }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "maybe" ] ], [ "maybe" ] ) [ itemType ] ->
            { function = codecsModule "encodeMaybe"
            , arguments =
                [ specificEncoderForType customTypeVars itemType
                , valueArg
                ]
            }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "dict" ] ) [ dictKeyType, dictValType ] ->
            { function = codecsModule "encodeDict"
            , arguments =
                {--encodeKey --}
                [ specificEncoderForType customTypeVars dictKeyType

                {--encodeValue --}
                , specificEncoderForType customTypeVars dictValType
                , valueArg
                ]
            }

        Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ listType ] ->
            { function = codecsModule "encodeList"
            , arguments =
                [ specificEncoderForType customTypeVars listType
                , valueArg
                ]
            }

        Type.Record _ fieldList ->
            { function = codecsModule "encodeRecord"
            , arguments =
                {--fieldEncoders --}
                [ (fieldList
                    |> List.map
                        (\field ->
                            TS.ArrayLiteralExpression
                                [ TS.StringLiteralExpression (Name.toCamelCase field.name)
                                , specificEncoderForType customTypeVars field.tpe
                                ]
                        )
                  )
                    |> TS.ArrayLiteralExpression
                    |> buildCodecMap
                , valueArg
                ]
            }

        Type.Tuple _ tupleTypesList ->
            { function = codecsModule "encodeTuple"
            , arguments =
                {--elementEncoders --}
                [ TS.ArrayLiteralExpression
                    (List.map (specificEncoderForType customTypeVars) tupleTypesList)
                , valueArg
                ]
            }

        Type.Variable _ varName ->
            { function =
                TS.Identifier (prependEncodeToName varName)
            , arguments = [ valueArg ]
            }

        Type.Reference _ fQName argTypes ->
            let
                decoderName =
                    prependEncodeToName (FQName.getLocalName fQName)

                varEncoders =
                    argTypes |> List.map (specificEncoderForType customTypeVars)
            in
            { function = referenceCodec fQName decoderName
            , arguments = varEncoders ++ [ valueArg ]
            }

        Type.Unit _ ->
            { function = codecsModule "encodeUnit"
            , arguments = [ valueArg ]
            }

        {--Unhandled types are treated as Unit --}
        _ ->
            { function = codecsModule "encodeUnit"
            , arguments = [ valueArg ]
            }


specificEncoderForType : TypeVariablesList -> Type.Type ta -> TS.Expression
specificEncoderForType customTypeVars typeExp =
    let
        expression =
            encoderExpression customTypeVars typeExp (TS.Identifier "value")

        removeValueArg arguments =
            arguments |> List.take (List.length arguments - 1)
    in
    bindArgumentsToFunction expression.function (removeValueArg expression.arguments)


generateEncoderFunction : TypeVariablesList -> Name -> Access -> Type.Type ta -> TS.Statement
generateEncoderFunction variables typeName access typeExp =
    let
        variableTypeExpressions : List TS.TypeExp
        variableTypeExpressions =
            variables |> List.map Name.toTitleCase |> List.map (\var -> TS.Variable var)

        call =
            encoderExpression variables typeExp (TS.Identifier "value")

        variableParams : List TS.Parameter
        variableParams =
            variables
                |> List.map
                    (\var ->
                        TS.parameter
                            []
                            (prependEncodeToName var)
                            (Just (encoderTypeSignature (TS.Variable (Name.toTitleCase var))))
                    )

        valueParam : TS.Parameter
        valueParam =
            TS.parameter [] "value" (Just (TS.TypeRef ( [], [], typeName ) variableTypeExpressions))
    in
    TS.FunctionDeclaration
        { name = prependEncodeToName typeName
        , typeVariables = variableTypeExpressions
        , returnType = Just TS.Any
        , scope = TS.ModuleFunction
        , parameters = variableParams ++ [ valueParam ]
        , privacy = access |> mapPrivacy
        , body = [ TS.ReturnStatement (call |> TS.Call) ]
        }


generateConstructorEncoderFunction : ConstructorDetail ta -> TS.Statement
generateConstructorEncoderFunction constructor =
    let
        variableTypeExpressions : List TS.TypeExp
        variableTypeExpressions =
            constructor.typeVariableNames |> List.map Name.toTitleCase |> List.map (\var -> TS.Variable var)

        encoderParams : List TS.Parameter
        encoderParams =
            constructor.typeVariableNames
                |> List.map
                    (\var ->
                        TS.parameter
                            []
                            (prependEncodeToName var)
                            (Just (encoderTypeSignature (TS.Variable (Name.toTitleCase var))))
                    )

        valueParam : TS.Parameter
        valueParam =
            TS.parameter [] "value" (Just (TS.TypeRef ( [], [], constructor.name ) variableTypeExpressions))

        argToEncoderCall : ( Name, Type a ) -> TS.Expression
        argToEncoderCall ( argName, argType ) =
            TS.Call
                (encoderExpression
                    constructor.typeVariableNames
                    argType
                    (TS.MemberExpression
                        { object = TS.Identifier "value"
                        , member = argName |> Name.toCamelCase |> TS.Identifier
                        }
                    )
                )

        kindExpression : TS.Expression
        kindExpression =
            TS.MemberExpression { object = TS.Identifier "value", member = TS.Identifier "kind" }

        returnList : TS.Expression
        returnList =
            if (constructor.args |> List.length) == 0 then
                kindExpression

            else
                TS.ArrayLiteralExpression
                    (kindExpression
                        :: (constructor.args |> List.map argToEncoderCall)
                    )
    in
    TS.FunctionDeclaration
        { name = prependEncodeToName constructor.name
        , typeVariables = variableTypeExpressions
        , returnType = Just TS.Any
        , scope = TS.ModuleFunction
        , privacy = constructor.privacy
        , parameters = encoderParams ++ [ valueParam ]
        , body = [ TS.ReturnStatement returnList ]
        }


generateUnionEncoderFunction : Name -> TS.Privacy -> List Name -> List (ConstructorDetail ta) -> TS.Statement
generateUnionEncoderFunction typeName privacy typeVariables constructors =
    let
        variableTypeExpressions : List TS.TypeExp
        variableTypeExpressions =
            typeVariables |> List.map Name.toTitleCase |> List.map (\var -> TS.Variable var)

        encoderParams : List TS.Parameter
        encoderParams =
            typeVariables
                |> List.map
                    (\var ->
                        TS.parameter
                            []
                            (prependEncodeToName var)
                            (Just (encoderTypeSignature (TS.Variable (Name.toTitleCase var))))
                    )

        valueParam : TS.Parameter
        valueParam =
            TS.parameter [] "value" (Just (TS.TypeRef ( [], [], typeName ) variableTypeExpressions))

        constructorToCaseBlock : ConstructorDetail ta -> ( TS.Expression, List TS.Statement )
        constructorToCaseBlock constructor =
            ( constructor.name |> Name.toTitleCase |> TS.StringLiteralExpression
            , [ TS.ReturnStatement
                    (TS.Call
                        { function = constructor.name |> prependEncodeToName |> TS.Identifier
                        , arguments = (constructor.typeVariableNames |> List.map (prependEncodeToName >> TS.Identifier)) ++ [ TS.Identifier "value" ]
                        }
                    )
              ]
            )

        switchStatement : TS.Statement
        switchStatement =
            TS.SwitchStatement
                (TS.MemberExpression { object = TS.Identifier "value", member = TS.Identifier "kind" })
                (constructors |> List.map constructorToCaseBlock)
    in
    TS.FunctionDeclaration
        { name = prependEncodeToName typeName
        , typeVariables = variableTypeExpressions
        , returnType = Just TS.Any
        , scope = TS.ModuleFunction
        , privacy = privacy
        , parameters = encoderParams ++ [ valueParam ]
        , body = [ switchStatement ]
        }


generateConstructorConstructorFunction : ConstructorDetail ta -> TS.Statement
generateConstructorConstructorFunction { name, privacy, args, typeVariables, typeVariableNames } =
    let
        argParams : List TS.Parameter
        argParams =
            args
                |> List.map
                    (\( argName, argType ) ->
                        TS.parameter [ "public" ] (argName |> Name.toCamelCase) (Just (mapTypeExp argType))
                    )
    in
    TS.FunctionDeclaration
        { name = "constructor"
        , typeVariables = []
        , returnType = Nothing
        , scope = TS.ClassMemberFunction
        , privacy = privacy
        , parameters = argParams
        , body = []
        }
