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


module Morphir.IR.SDK.Char exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path
import Morphir.IR.SDK.Basics exposing (boolType, intType)
import Morphir.IR.SDK.Common exposing (toFQName, vSpec)
import Morphir.IR.Type exposing (Specification(..), Type(..))


moduleName : ModuleName
moduleName =
    Path.fromString "Char"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Char", OpaqueTypeSpecification [] |> Documented "Type that represents a single character." )
            ]
    , values =
        Dict.fromList
            [ vSpec "isUpper" [ ( "c", charType () ) ] (boolType ())
            , vSpec "isLower" [ ( "c", charType () ) ] (boolType ())
            , vSpec "isAlpha" [ ( "c", charType () ) ] (boolType ())
            , vSpec "isAlphaNum" [ ( "c", charType () ) ] (boolType ())
            , vSpec "isDigit" [ ( "c", charType () ) ] (boolType ())
            , vSpec "isOctDigit" [ ( "c", charType () ) ] (boolType ())
            , vSpec "isHexDigit" [ ( "c", charType () ) ] (boolType ())
            , vSpec "toUpper" [ ( "c", charType () ) ] (charType ())
            , vSpec "toLower" [ ( "c", charType () ) ] (charType ())
            , vSpec "toLocaleUpper" [ ( "c", charType () ) ] (charType ())
            , vSpec "toLocaleLower" [ ( "c", charType () ) ] (charType ())
            , vSpec "toCode" [ ( "c", charType () ) ] (intType ())
            , vSpec "fromCode" [ ( "c", intType () ) ] (charType ())
            ]
    , doc = Just "Contains the Char type representing a single character, and it's associated functions."
    }


charType : a -> Type a
charType attributes =
    Reference attributes (toFQName moduleName "Char") []
