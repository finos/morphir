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


module Morphir.IR.SDK.Tuple exposing (..)

import Dict
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (tFun, tVar, vSpec)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value


moduleName : ModuleName
moduleName =
    Path.fromString "Tuple"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.empty
    , values =
        Dict.fromList
            [ vSpec "pair"
                [ ( "a", tVar "b" )
                , ( "b", tVar "b" )
                ]
                (Type.Tuple () [ tVar "a", tVar "b" ])
            , vSpec "first"
                [ ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (tVar "a")
            , vSpec "second"
                [ ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (tVar "b")
            , vSpec "mapFirst"
                [ ( "f", tFun [ tVar "a" ] (tVar "x") )
                , ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (Type.Tuple () [ tVar "x", tVar "b" ])
            , vSpec "mapSecond"
                [ ( "f", tFun [ tVar "b" ] (tVar "y") )
                , ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (Type.Tuple () [ tVar "a", tVar "y" ])
            , vSpec "mapBoth"
                [ ( "f", tFun [ tVar "a" ] (tVar "x") )
                , ( "g", tFun [ tVar "b" ] (tVar "y") )
                , ( "tuple", Type.Tuple () [ tVar "a", tVar "b" ] )
                ]
                (Type.Tuple () [ tVar "x", tVar "y" ])
            ]
    }
