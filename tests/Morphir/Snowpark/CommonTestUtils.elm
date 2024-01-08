module Morphir.Snowpark.CommonTestUtils exposing (..)

import Dict exposing (Dict(..))
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.FQName as FQName
import Morphir.IR.Literal as Literal
import Morphir.IR.Module exposing (emptyDefinition)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.MapFunctionsMapping
    exposing
        ( basicsFunctionName
        , dictFunctionName
        , listFunctionName
        , maybeFunctionName
        )


morphirNamespace : List (List String)
morphirNamespace =
    [ [ "morphir" ], [ "s", "d", "k" ] ]


stringTypeInstance : Type.Type ()
stringTypeInstance =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) []


boolTypeInstance : Type.Type ()
boolTypeInstance =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) []


intTypeInstance : Type.Type ()
intTypeInstance =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) []


floatTypeInstance : Type.Type ()
floatTypeInstance =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) []


aggregateTypeInstance : Name.Name -> List (Type.Type ()) -> Type.Type ()
aggregateTypeInstance name args =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "aggregate" ] ], name ) args


testDistributionName : Path.Path
testDistributionName =
    Path.fromString "UTest"


typesDict =
    Dict.fromList
        [ ( Name.fromString "Emp"
          , public
                { doc = ""
                , value =
                    Type.TypeAliasDefinition []
                        (Type.Record ()
                            [ { name = Name.fromString "firstname", tpe = stringTypeInstance }
                            , { name = Name.fromString "lastname", tpe = stringTypeInstance }
                            ]
                        )
                }
          )
        , ( Name.fromString "EmployeeInfo"
          , public
                { doc = ""
                , value =
                    Type.TypeAliasDefinition []
                        (Type.Record ()
                            [ { name = Name.fromString "employee", tpe = stringTypeInstance }
                            , { name = Name.fromString "minSalary", tpe = floatTypeInstance }
                            ]
                        )
                }
          )
        , ( Name.fromString "TypeA"
          , public
                { doc = ""
                , value =
                    Type.TypeAliasDefinition []
                        (Type.Record ()
                            [ { name = Name.fromString "id", tpe = intTypeInstance }
                            ]
                        )
                }
          )
        , ( Name.fromString "TypeB"
          , public
                { doc = ""
                , value =
                    Type.TypeAliasDefinition []
                        (Type.Record ()
                            [ { name = Name.fromString "id", tpe = intTypeInstance }
                            ]
                        )
                }
          )
        , ( Name.fromString "TypeC"
          , public
                { doc = ""
                , value =
                    Type.TypeAliasDefinition []
                        (Type.Record ()
                            [ { name = Name.fromString "id", tpe = intTypeInstance }
                            ]
                        )
                }
          )
        , ( Name.fromString "DeptKind"
          , public
                { doc = ""
                , value =
                    Type.CustomTypeDefinition []
                        (public
                            (Dict.fromList
                                [ ( Name.fromString "Hr", [] )
                                , ( Name.fromString "It", [] )
                                , ( Name.fromString "Logic", [] )
                                ]
                            )
                        )
                }
          )
        , ( Name.fromString "TimeRange"
          , public
                { doc = ""
                , value =
                    Type.CustomTypeDefinition []
                        (public
                            (Dict.fromList
                                [ ( Name.fromString "Zero", [] )
                                , ( Name.fromString "Seconds", [ ( [ "a1" ], intTypeInstance ) ] )
                                , ( Name.fromString "MinutesAndSeconds", [ ( [ "a1" ], intTypeInstance ), ( [ "a2" ], intTypeInstance ) ] )
                                ]
                            )
                        )
                }
          )
        ]


testDistributionPackage =
    { modules =
        Dict.fromList
            [ ( Path.fromString "MyMod"
              , public { emptyDefinition | types = typesDict }
              )
            ]
    }


mStringLiteralOf : String -> Value.TypedValue
mStringLiteralOf value =
    Value.Literal stringTypeInstance (Literal.StringLiteral value)


mIntLiteralOf : Int -> Value.TypedValue
mIntLiteralOf value =
    Value.Literal intTypeInstance (Literal.WholeNumberLiteral value)


mFloatLiteralOf : Float -> Value.TypedValue
mFloatLiteralOf value =
    Value.Literal floatTypeInstance (Literal.FloatLiteral value)


mListTypeOf : Type.Type () -> Type.Type ()
mListTypeOf tpe =
    Type.Reference () (listFunctionName [ "list" ]) [ tpe ]


mDictTypeOf : Type.Type () -> Type.Type () -> Type.Type ()
mDictTypeOf key value =
    Type.Reference () (dictFunctionName [ "dict" ]) [ key, value ]


mFuncTypeOf : Type.Type () -> Type.Type () -> Type.Type ()
mFuncTypeOf from to =
    Type.Function () from to


mRecordTypeOf : List ( String, Type.Type () ) -> Type.Type ()
mRecordTypeOf fields =
    Type.Record () (List.map (\( name, tpe ) -> { name = [ name ], tpe = tpe }) fields)


mRecordOf : List ( String, Value.TypedValue ) -> Value.TypedValue
mRecordOf fields =
    Value.Record
        (mRecordTypeOf (List.map (\( name, val ) -> ( name, Value.valueAttribute val )) fields))
        (fields
            |> List.map (\( name, val ) -> ( [ name ], val ))
            |> Dict.fromList
        )


listConcatMapFunction : Type.Type () -> Type.Type () -> Value.TypedValue
listConcatMapFunction collectionFrom collectionTo =
    Value.Reference
        (mFuncTypeOf
            (mFuncTypeOf collectionFrom (mListTypeOf collectionTo))
            (mFuncTypeOf (mListTypeOf collectionFrom) (mListTypeOf collectionTo))
        )
        (listFunctionName [ "concat", "map" ])


listFilterMapFunction : Type.Type () -> Type.Type () -> Value.TypedValue
listFilterMapFunction collectionFrom collectionTo =
    Value.Reference
        (mFuncTypeOf
            (mFuncTypeOf collectionFrom (mMaybeTypeOf collectionTo))
            (mFuncTypeOf (mListTypeOf collectionFrom) (mListTypeOf collectionTo))
        )
        (listFunctionName [ "filter", "map" ])


equalFunction : Type.Type () -> Value.TypedValue
equalFunction tpe =
    Value.Reference
        (mFuncTypeOf tpe (mFuncTypeOf tpe boolTypeInstance))
        (basicsFunctionName [ "equal" ])


addFunction : Type.Type () -> Value.TypedValue
addFunction tpe =
    Value.Reference
        (mFuncTypeOf tpe (mFuncTypeOf tpe tpe))
        (basicsFunctionName [ "add" ])


listMapFunction : Type.Type () -> Type.Type () -> Value.TypedValue
listMapFunction collectionFrom collectionTo =
    Value.Reference
        (mFuncTypeOf
            (mFuncTypeOf collectionFrom collectionTo)
            (mFuncTypeOf (mListTypeOf collectionFrom) (mListTypeOf collectionTo))
        )
        (listFunctionName [ "map" ])


groupByFunction : Type.Type () -> Type.Type () -> Value.TypedValue
groupByFunction key a =
    Value.Reference
        (mFuncTypeOf
            (mFuncTypeOf a key)
            (mFuncTypeOf (mListTypeOf a) (mDictTypeOf key (mListTypeOf a)))
        )
        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "aggregate" ] ], [ "group", "by" ] )


aggregateFunction : Type.Type () -> Type.Type () -> Type.Type () -> Value.TypedValue
aggregateFunction key a b =
    Value.Reference
        (mFuncTypeOf
            (mFuncTypeOf key (mFuncTypeOf (aggregatorType a key0Type) b))
            (mFuncTypeOf (mDictTypeOf key (mListTypeOf a)) (mListTypeOf b))
        )
        ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "aggregate" ] ], [ "aggregate" ] )


aggregatorType : Type.Type () -> Type.Type () -> Type.Type ()
aggregatorType a key =
    aggregateTypeInstance [ "aggregator" ] [ a, key ]


key0Type : Type.Type ()
key0Type =
    Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "key" ] ], [ "key", "0" ] ) []


listFilterFunction : Type.Type () -> Type.Type () -> Value.TypedValue
listFilterFunction collectionFrom collectionTo =
    Value.Reference
        (mFuncTypeOf
            (mFuncTypeOf collectionFrom boolTypeInstance)
            (mFuncTypeOf (mListTypeOf collectionFrom) (mListTypeOf collectionTo))
        )
        (listFunctionName [ "filter" ])


listConcatFunction : Type.Type () -> Value.TypedValue
listConcatFunction collectionElementType =
    Value.Reference
        (mFuncTypeOf
            (mListTypeOf (mListTypeOf collectionElementType))
            (mListTypeOf collectionElementType)
        )
        (listFunctionName [ "concat" ])


listSumFunction : Type.Type () -> Value.TypedValue
listSumFunction collectionElementType =
    Value.Reference
        (mFuncTypeOf
            (mListTypeOf collectionElementType)
            collectionElementType
        )
        (listFunctionName [ "sum" ])


maybeMapFunction : Type.Type () -> Type.Type () -> Value.TypedValue
maybeMapFunction innerType targetType =
    Value.Reference
        (mFuncTypeOf
            (mFuncTypeOf innerType targetType)
            (mFuncTypeOf
                (mMaybeTypeOf innerType)
                (mMaybeTypeOf targetType)
            )
        )
        (maybeFunctionName [ "map" ])


maybeWithDefaultFunction : Type.Type () -> Value.TypedValue
maybeWithDefaultFunction innerType =
    Value.Reference
        (mFuncTypeOf
            innerType
            (mMaybeTypeOf innerType)
        )
        (maybeFunctionName [ "with", "default" ])


mLambdaOf : ( Name.Name, Type.Type () ) -> Value.TypedValue -> Value.TypedValue
mLambdaOf ( name, tpe ) body =
    Value.Lambda
        (mFuncTypeOf tpe (Value.valueAttribute body))
        (Value.AsPattern tpe (Value.WildcardPattern tpe) name)
        body


mListOf : List Value.TypedValue -> Value.TypedValue
mListOf values =
    let
        tpe =
            values
                |> List.head
                |> Maybe.map (\e -> Value.valueAttribute e)
                |> Maybe.withDefault (Type.Unit ())
    in
    Value.List (mListTypeOf tpe) values


mReferenceType : FQName.FQName -> List (Type.Type ()) -> Type.Type ()
mReferenceType name list =
    Type.Reference () name list


mLetOf : Name.Name -> Value.TypedValue -> Value.TypedValue -> Value.TypedValue
mLetOf name localValue body =
    Value.LetDefinition
        (Value.valueAttribute body)
        name
        { inputTypes = []
        , outputType = Value.valueAttribute localValue
        , body = localValue
        }
        body


mMaybeTypeOf : Type.Type () -> Type.Type ()
mMaybeTypeOf tpe =
    Type.Reference () (maybeFunctionName [ "maybe" ]) [ tpe ]


empType =
    Type.Reference () (FQName.fromString "UTest:MyMod:Emp" ":") []


employeeInfo =
    Type.Reference () (FQName.fromString "UTest:MyMod:EmployeeInfo" ":") []


typeA =
    Type.Reference () (FQName.fromString "UTest:MyMod:TypeA" ":") []


typeB =
    Type.Reference () (FQName.fromString "UTest:MyMod:TypeB" ":") []


typeC =
    Type.Reference () (FQName.fromString "UTest:MyMod:TypeC" ":") []


mIdOf : Name.Name -> Type.Type () -> Value.TypedValue
mIdOf name tpe =
    Value.Variable tpe name


sCall : ( Scala.Value, String ) -> List Scala.Value -> Scala.Value
sCall ( obj, memberName ) args =
    Scala.Apply (Scala.Select obj memberName) (List.map (\arg -> Scala.ArgValue Nothing arg) args)


sExpCall : Scala.Value -> List Scala.Value -> Scala.Value
sExpCall exp args =
    Scala.Apply exp (List.map (\arg -> Scala.ArgValue Nothing arg) args)


sVar : String -> Scala.Value
sVar name =
    Scala.Variable name


sDot : Scala.Value -> String -> Scala.Value
sDot expr memberName =
    Scala.Select expr memberName


sSnowparkRefFuncion : String -> Scala.Value
sSnowparkRefFuncion name =
    Scala.Ref [ "com", "snowflake", "snowpark", "functions" ] name


sLit : String -> Scala.Value
sLit stringLit =
    Scala.Literal (Scala.StringLit stringLit)


sIntLit : Int -> Scala.Value
sIntLit intLiteral =
    Scala.Literal (Scala.IntegerLit intLiteral)


sFloatLit : Float -> Scala.Value
sFloatLit floatLiteral =
    Scala.Literal (Scala.FloatLit floatLiteral)


sTrue : Scala.Value
sTrue =
    Scala.Literal (Scala.BooleanLit True)


sFalse : Scala.Value
sFalse =
    Scala.Literal (Scala.BooleanLit False)


sSpEqual : Scala.Value -> Scala.Value -> Scala.Value
sSpEqual left right =
    Scala.BinOp left "===" right


sBlock : Scala.Value -> List ( Scala.Name, Scala.Value ) -> Scala.Value
sBlock body bindings =
    let
        valDecls =
            bindings
                |> List.map
                    (\( name, value ) ->
                        Scala.ValueDecl
                            { modifiers = []
                            , pattern = Scala.NamedMatch name
                            , valueType = Nothing
                            , value = value
                            }
                    )
    in
    Scala.Block valDecls body


innerJoinFunction : Type.Type () -> Type.Type () -> Value.TypedValue
innerJoinFunction collectionA collectionB =
    Value.Reference
        (mFuncTypeOf
            (mListTypeOf collectionB)
            (mFuncTypeOf
                (mFuncTypeOf collectionA
                    (mFuncTypeOf collectionB boolTypeInstance)
                )
                (mFuncTypeOf
                    (mListTypeOf collectionA)
                    (mListTypeOf (mTuple2TypeOf collectionA collectionB))
                )
            )
        )
        (listFunctionName [ "inner", "join" ])


leftJoinFunction : Type.Type () -> Type.Type () -> Value.TypedValue
leftJoinFunction collectionA collectionB =
    Value.Reference
        (mFuncTypeOf
            (mListTypeOf collectionB)
            (mFuncTypeOf
                (mFuncTypeOf collectionA
                    (mFuncTypeOf collectionB boolTypeInstance)
                )
                (mFuncTypeOf
                    (mListTypeOf collectionA)
                    (mListTypeOf (mTuple2TypeOf collectionA (mMaybeTypeOf collectionB)))
                )
            )
        )
        (listFunctionName [ "left", "join" ])


mTuple2TypeOf : Type.Type () -> Type.Type () -> Type.Type ()
mTuple2TypeOf tpe1 tpe2 =
    Type.Tuple () [ tpe1, tpe2 ]


mField : Type.Type () -> Value.TypedValue -> String -> Value.TypedValue
mField tpe value name =
    Value.Field tpe value [ name ]


mFieldFunction : Type.Type () -> Name.Name -> Value.TypedValue
mFieldFunction a name =
    Value.FieldFunction a name
