{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.IR.SDK.Dict exposing (dictType, fromListValue, moduleName, moduleSpec, nativeFunctions)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.Common exposing (tFun, tVar, toFQName, vSpec)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.Maybe exposing (just, maybeType, nothing)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value exposing (Value)
import Morphir.Value.Error exposing (Error(..))
import Morphir.Value.Native as Native


moduleName : ModuleName
moduleName =
    Path.fromString "Dict"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Dict", OpaqueTypeSpecification [ [ "k", "v" ] ] |> Documented "Type that represents a dictionary of key-value pairs." )
            ]
    , values =
        Dict.fromList
            [ vSpec "empty" [] (dictType () (tVar "k") (tVar "v"))
            , vSpec "singleton" [ ( "key", tVar "comparable" ), ( "value", tVar "v" ) ] (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "insert"
                [ ( "key", tVar "comparable" )
                , ( "value", tVar "v" )
                , ( "dict", dictType () (tVar "comparable") (tVar "v") )
                ]
                (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "update"
                [ ( "key", tVar "comparable" )
                , ( "f", tFun [ maybeType () (tVar "v") ] (maybeType () (tVar "v")) )
                , ( "dict", dictType () (tVar "comparable") (tVar "v") )
                ]
                (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "remove"
                [ ( "key", tVar "comparable" )
                , ( "dict", dictType () (tVar "comparable") (tVar "v") )
                ]
                (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "isEmpty" [ ( "dict", dictType () (tVar "comparable") (tVar "v") ) ] (boolType ())
            , vSpec "member" [ ( "key", tVar "comparable" ), ( "dict", dictType () (tVar "comparable") (tVar "v") ) ] (boolType ())
            , vSpec "get" [ ( "key", tVar "comparable" ), ( "dict", dictType () (tVar "comparable") (tVar "v") ) ] (maybeType () (tVar "v"))
            , vSpec "size" [ ( "dict", dictType () (tVar "comparable") (tVar "v") ) ] (intType ())
            , vSpec "keys" [ ( "dict", dictType () (tVar "k") (tVar "v") ) ] (listType () (tVar "k"))
            , vSpec "values" [ ( "dict", dictType () (tVar "k") (tVar "v") ) ] (listType () (tVar "v"))
            , vSpec "toList" [ ( "dict", dictType () (tVar "k") (tVar "v") ) ] (listType () (Type.Tuple () [ tVar "k", tVar "v" ]))
            , vSpec "fromList" [ ( "list", listType () (Type.Tuple () [ tVar "comparable", tVar "v" ]) ) ] (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "map"
                [ ( "f", tFun [ tVar "k", tVar "a" ] (tVar "b") )
                , ( "dict", dictType () (tVar "k") (tVar "a") )
                ]
                (dictType () (tVar "k") (tVar "b"))
            , vSpec "foldl"
                [ ( "f", tFun [ tVar "k", tVar "v", tVar "b" ] (tVar "b") )
                , ( "z", tVar "b" )
                , ( "list", dictType () (tVar "k") (tVar "v") )
                ]
                (tVar "b")
            , vSpec "foldr"
                [ ( "f", tFun [ tVar "k", tVar "v", tVar "b" ] (tVar "b") )
                , ( "z", tVar "b" )
                , ( "list", dictType () (tVar "k") (tVar "v") )
                ]
                (tVar "b")
            , vSpec "filter"
                [ ( "f", tFun [ tVar "comparable", tVar "v" ] (boolType ()) )
                , ( "dict", dictType () (tVar "comparable") (tVar "v") )
                ]
                (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "partition"
                [ ( "f", tFun [ tVar "comparable", tVar "v" ] (boolType ()) )
                , ( "dict", dictType () (tVar "comparable") (tVar "v") )
                ]
                (Type.Tuple () [ dictType () (tVar "comparable") (tVar "v"), dictType () (tVar "comparable") (tVar "v") ])
            , vSpec "union"
                [ ( "dict1", dictType () (tVar "comparable") (tVar "v") )
                , ( "dict2", dictType () (tVar "comparable") (tVar "v") )
                ]
                (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "intersect"
                [ ( "dict1", dictType () (tVar "comparable") (tVar "v") )
                , ( "dict2", dictType () (tVar "comparable") (tVar "v") )
                ]
                (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "diff"
                [ ( "dict1", dictType () (tVar "comparable") (tVar "v") )
                , ( "dict2", dictType () (tVar "comparable") (tVar "v") )
                ]
                (dictType () (tVar "comparable") (tVar "v"))
            , vSpec "merge"
                [ ( "leftOnly", tFun [ tVar "comparable", tVar "a", tVar "result" ] (tVar "result") )
                , ( "both", tFun [ tVar "comparable", tVar "a", tVar "b", tVar "result" ] (tVar "result") )
                , ( "rightOnly", tFun [ tVar "comparable", tVar "b", tVar "result" ] (tVar "result") )
                , ( "dictLeft", dictType () (tVar "comparable") (tVar "a") )
                , ( "dictRight", dictType () (tVar "comparable") (tVar "b") )
                , ( "input", tVar "result" )
                ]
                (tVar "result")
            ]
    }


dictType : a -> Type a -> Type a -> Type a
dictType attributes keyType valueType =
    Reference attributes (toFQName moduleName "dict") [ keyType, valueType ]


fromListValue : va -> Value ta va -> Value ta va
fromListValue a list =
    Value.Apply a (Value.Reference a ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "from", "list" ] )) list


nativeFunctions : List ( String, Native.Function )
nativeFunctions =
    [ ( "fromList", Native.unaryStrict (\_ arg -> Ok (fromListValue () arg)) )
    , ( "get"
      , Native.binaryStrict
            (\keyToGet dict ->
                case dict of
                    Value.Apply _ (Value.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "from", "list" ] )) arg ->
                        case arg of
                            Value.List _ list ->
                                let
                                    find l =
                                        case l of
                                            [] ->
                                                Ok (nothing ())

                                            head :: tail ->
                                                case head of
                                                    Value.Tuple _ [ key, value ] ->
                                                        if key == keyToGet then
                                                            Ok (just () value)

                                                        else
                                                            find tail

                                                    _ ->
                                                        Err TupleExpected
                                in
                                find list

                            _ ->
                                Err (ExpectedList arg)

                    _ ->
                        Err (UnexpectedArguments [ dict ])
            )
      )
    ]
