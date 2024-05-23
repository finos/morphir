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


module Morphir.IR.SDK.Regex exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.Common exposing (tFun, toFQName, vSpec)
import Morphir.IR.SDK.List exposing (listType)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.SDK.String exposing (stringType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value


moduleName : ModuleName
moduleName =
    Path.fromString "Regex"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Regex", OpaqueTypeSpecification [] |> Documented "Type that represents regular expressions" )
            , ( Name.fromString "Options"
              , TypeAliasSpecification []
                    (Type.Record ()
                        [ Type.Field [ "case", "insensitive" ] (boolType ())
                        , Type.Field [ "multiline" ] (boolType ())
                        ]
                    )
                    |> Documented "Type that represents Regex options"
              )
            , ( Name.fromString "Match"
              , TypeAliasSpecification []
                    (Type.Record ()
                        [ Type.Field [ "match" ] (stringType ())
                        , Type.Field [ "index" ] (intType ())
                        , Type.Field [ "number" ] (intType ())
                        , Type.Field [ "submatches" ] (listType () (maybeType () (stringType ())))
                        ]
                    )
                    |> Documented "Type that represents a match"
              )
            ]
    , values =
        Dict.fromList
            [ vSpec "fromString"
                [ ( "string", stringType () )
                ]
                (maybeType () (regexType ()))
            , vSpec "fromStringWith"
                [ ( "options", optionsType () )
                , ( "string", stringType () )
                ]
                (maybeType () (regexType ()))
            , vSpec "never"
                []
                (regexType ())
            , vSpec "contains"
                [ ( "regex", regexType () )
                , ( "string", stringType () )
                ]
                (boolType ())
            , vSpec "split"
                [ ( "regex", regexType () )
                , ( "string", stringType () )
                ]
                (listType () (stringType ()))
            , vSpec "find"
                [ ( "regex", regexType () )
                , ( "string", stringType () )
                ]
                (listType () (matchType ()))
            , vSpec "replace"
                [ ( "regex", regexType () )
                , ( "with", tFun [ matchType () ] (stringType ()) )
                , ( "string", stringType () )
                ]
                (stringType ())
            , vSpec "splitAtMost"
                [ ( "number", intType () )
                , ( "regex", regexType () )
                , ( "string", stringType () )
                ]
                (listType () (stringType ()))
            , vSpec "findAtMost"
                [ ( "number", intType () )
                , ( "regex", regexType () )
                , ( "string", stringType () )
                ]
                (listType () (matchType ()))
            , vSpec "replaceAtMost"
                [ ( "number", intType () )
                , ( "regex", regexType () )
                , ( "with", tFun [ matchType () ] (stringType ()) )
                , ( "string", stringType () )
                ]
                (stringType ())
            ]
    , doc = Just "Regular Expressions and related functions."
    }


regexType : a -> Type a
regexType attributes =
    Type.Reference attributes (toFQName moduleName "Regex") []


optionsType : a -> Type a
optionsType attributes =
    Type.Reference attributes (toFQName moduleName "Options") []


matchType : a -> Type a
matchType attributes =
    Type.Reference attributes (toFQName moduleName "Match") []
