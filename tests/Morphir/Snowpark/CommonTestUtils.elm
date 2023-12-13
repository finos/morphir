module Morphir.Snowpark.CommonTestUtils exposing (..)

import Dict exposing (Dict(..))
import Morphir.IR.Type as Type
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.Literal as Literal
import Morphir.IR.Value as Value
import Morphir.Snowpark.MapFunctionsMapping exposing (basicsFunctionName, listFunctionName, maybeFunctionName)
import Morphir.IR.AccessControlled exposing (public)
import Morphir.IR.Module exposing (emptyDefinition)
import Morphir.IR.Name as Name
import Morphir.Scala.AST as Scala
import Morphir.IR.FQName as FQName

morphirNamespace : List (List String)
morphirNamespace = [["morphir"],["s","d","k"]]

stringTypeInstance : Type.Type ()
stringTypeInstance = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "string" ] ], [ "string" ] ) []
boolTypeInstance : Type.Type ()
boolTypeInstance = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "bool" ] ) []

intTypeInstance : Type.Type ()
intTypeInstance = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "int" ] ) []

floatTypeInstance : Type.Type ()
floatTypeInstance = Type.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "basics" ] ], [ "float" ] ) []

testDistributionName : Path.Path
testDistributionName = (Path.fromString "UTest") 

typesDict = 
    Dict.fromList [
        -- A record with simple types
        (Name.fromString "Emp", 
        public { doc =  "", value = Type.TypeAliasDefinition [] (Type.Record () [
            { name = Name.fromString "firstname", tpe = stringTypeInstance },
            { name = Name.fromString "lastname", tpe = stringTypeInstance }
        ]) })
        , (Name.fromString "DeptKind", 
                 public { doc =  "", value = Type.CustomTypeDefinition [] (public (Dict.fromList [
                    (Name.fromString "Hr", [] ),
                    (Name.fromString "It", [] ),
                    (Name.fromString "Logic", [] )
                 ])) })
        , (Name.fromString "TimeRange", 
                 public { doc =  "", value = Type.CustomTypeDefinition [] (public (Dict.fromList [
                    (Name.fromString "Zero", [] ),
                    (Name.fromString "Seconds", [ (["a1"], intTypeInstance) ]),
                    (Name.fromString "MinutesAndSeconds", [ (["a1"], intTypeInstance), (["a2"], intTypeInstance) ])
                 ])) })
    ]

testDistributionPackage = 
        ({ modules = Dict.fromList [
            ( Path.fromString "MyMod",
              public { emptyDefinition | types = typesDict } )
        ]}) 

mStringLiteralOf : String -> Value.TypedValue
mStringLiteralOf value =
    Value.Literal stringTypeInstance (Literal.StringLiteral value)

mIntLiteralOf : Int -> Value.TypedValue
mIntLiteralOf value =
    Value.Literal intTypeInstance (Literal.WholeNumberLiteral value)

mListTypeOf : Type.Type () -> Type.Type ()
mListTypeOf tpe =
    Type.Reference () (listFunctionName [ "list" ]) [ tpe ]

mFuncTypeOf : Type.Type () -> Type.Type () -> Type.Type ()
mFuncTypeOf from to =
    Type.Function () from to

mRecordTypeOf : List (String, Type.Type ()) -> Type.Type ()
mRecordTypeOf fields =
    Type.Record () (List.map (\(name, tpe) -> { name = [name], tpe = tpe }) fields)

mRecordOf : List (String, Value.TypedValue) -> Value.TypedValue
mRecordOf fields =
    Value.Record 
        (mRecordTypeOf (List.map (\(name, val) -> (name, Value.valueAttribute val)) fields ))
        (fields 
            |> List.map (\(name, val) -> ([ name ], val)) 
            |> Dict.fromList)

listConcatMapFunction : Type.Type () -> Type.Type () -> Value.TypedValue
listConcatMapFunction collectionFrom collectionTo  =
    Value.Reference
        (mFuncTypeOf  
            (mFuncTypeOf collectionFrom (mListTypeOf collectionTo))
            (mFuncTypeOf (mListTypeOf collectionFrom) (mListTypeOf collectionTo)))
        (listFunctionName [ "concat", "map" ])

listFilterMapFunction : Type.Type () -> Type.Type () -> Value.TypedValue
listFilterMapFunction collectionFrom collectionTo  =
    Value.Reference
        (mFuncTypeOf  
            (mFuncTypeOf collectionFrom (mMaybeTypeOf collectionTo))
            (mFuncTypeOf (mListTypeOf collectionFrom) (mListTypeOf collectionTo)))
        (listFunctionName [ "filter", "map" ])

equalFunction : Type.Type () -> Value.TypedValue
equalFunction tpe  =
    Value.Reference
        (mFuncTypeOf tpe (mFuncTypeOf tpe boolTypeInstance))
        (basicsFunctionName [ "equal" ])

addFunction : Type.Type () -> Value.TypedValue
addFunction tpe  =
    Value.Reference
        (mFuncTypeOf tpe (mFuncTypeOf tpe tpe))
        (basicsFunctionName [ "add" ])


listMapFunction : Type.Type () -> Type.Type () -> Value.TypedValue
listMapFunction collectionFrom collectionTo  =
    Value.Reference
        (mFuncTypeOf  
            (mFuncTypeOf collectionFrom collectionTo)
            (mFuncTypeOf (mListTypeOf collectionFrom) (mListTypeOf collectionTo)))
        (listFunctionName [ "map" ])

listFilterFunction : Type.Type () -> Type.Type () -> Value.TypedValue
listFilterFunction collectionFrom collectionTo  =
    Value.Reference
        (mFuncTypeOf  
            (mFuncTypeOf collectionFrom boolTypeInstance)
            (mFuncTypeOf (mListTypeOf collectionFrom) (mListTypeOf collectionTo)))
        (listFunctionName [ "filter" ])

listConcatFunction : Type.Type () -> Value.TypedValue
listConcatFunction collectionElementType  =
    Value.Reference
        (mFuncTypeOf  
            (mListTypeOf (mListTypeOf collectionElementType))
            (mListTypeOf collectionElementType))
        (listFunctionName [ "concat" ])

listSumFunction : Type.Type () -> Value.TypedValue
listSumFunction collectionElementType  =
    Value.Reference
        (mFuncTypeOf  
            (mListTypeOf collectionElementType)
            collectionElementType)
        (listFunctionName [ "sum" ])

maybeMapFunction : Type.Type () -> Type.Type () -> Value.TypedValue
maybeMapFunction innerType targetType =
    Value.Reference
        (mFuncTypeOf  
            (mFuncTypeOf innerType targetType)
            (mFuncTypeOf  
                (mMaybeTypeOf innerType)
                (mMaybeTypeOf targetType)))
        (maybeFunctionName [ "map" ])

maybeWithDefaultFunction : Type.Type () -> Value.TypedValue
maybeWithDefaultFunction innerType  =
    Value.Reference
        (mFuncTypeOf  
            innerType
            (mMaybeTypeOf innerType))
        (maybeFunctionName [ "with", "default" ])

mLambdaOf : (Name.Name, Type.Type ()) -> Value.TypedValue -> Value.TypedValue
mLambdaOf (name, tpe) body =
    (Value.Lambda
        (mFuncTypeOf tpe (Value.valueAttribute body))
        (Value.AsPattern tpe (Value.WildcardPattern tpe) name)
        body)

mListOf : List Value.TypedValue  -> Value.TypedValue
mListOf values =
    let
        tpe = values 
                |> List.head 
                |> Maybe.map (\e -> Value.valueAttribute e)
                |> Maybe.withDefault (Type.Unit ())
    in
    Value.List (mListTypeOf tpe) values

mLetOf : Name.Name -> Value.TypedValue -> Value.TypedValue -> Value.TypedValue
mLetOf name localValue body =
    Value.LetDefinition
            (Value.valueAttribute body) 
            name
            { inputTypes = []
            , outputType = Value.valueAttribute localValue
            , body = localValue }
            body

mMaybeTypeOf : Type.Type () -> Type.Type ()
mMaybeTypeOf tpe =
    Type.Reference () (maybeFunctionName [ "maybe" ]) [ tpe ]

empType = Type.Reference () (FQName.fromString "UTest:MyMod:Emp" ":") []

mIdOf : Name.Name -> Type.Type () -> Value.TypedValue
mIdOf name tpe =
    Value.Variable tpe name

sCall : (Scala.Value, String) -> List Scala.Value -> Scala.Value
sCall (obj, memberName) args =
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

sLit : String -> Scala.Value
sLit stringLit =
    Scala.Literal (Scala.StringLit stringLit)    

sIntLit : Int -> Scala.Value
sIntLit intLiteral =
    Scala.Literal (Scala.IntegerLit intLiteral)

sTrue : Scala.Value
sTrue = 
    Scala.Literal (Scala.BooleanLit True)

sFalse : Scala.Value
sFalse = 
    Scala.Literal (Scala.BooleanLit False)

sSpEqual : Scala.Value -> Scala.Value -> Scala.Value
sSpEqual left right =
    Scala.BinOp left "===" right

sBlock : Scala.Value -> List (Scala.Name, Scala.Value) -> Scala.Value
sBlock body bindings =
    let
        valDecls =
            bindings 
                |> List.map (\(name, value) ->  
                                Scala.ValueDecl { modifiers = []
                                                , pattern = Scala.NamedMatch name
                                                , valueType = Nothing
                                                , value = value })
    in
    Scala.Block valDecls body