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


module Morphir.IR.SDK.StatefulApp exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Maybe exposing (maybeType)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value


moduleName : ModuleName
moduleName =
    Path.fromString "StatefulAp"


moduleSpec : Module.Specification ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "StatefulApp"
              , CustomTypeSpecification [ Name.fromString "k", Name.fromString "c", Name.fromString "s", Name.fromString "e" ]
                    -- StatefulApp (Maybe s -> c -> ( Maybe s, e ))
                    (Dict.fromList
                        [ ( Name.fromString "StatefulApp"
                          , [ ( Name.fromString "logic"
                                -- Maybe s -> c -> ( Maybe s, e )
                              , Type.Function ()
                                    (maybeType () (Type.Variable () (Name.fromString "s")))
                                    -- c -> ( Maybe s, e )
                                    (Type.Function ()
                                        (Type.Variable () (Name.fromString "c"))
                                        -- ( Maybe s, e )
                                        (Type.Tuple ()
                                            [ maybeType () (Type.Variable () (Name.fromString "s"))
                                            , Type.Variable () (Name.fromString "e")
                                            ]
                                        )
                                    )
                              )
                            ]
                          )
                        ]
                    )
                    |> Documented "Type that represents a stateful app."
              )
            ]
    , values =
        Dict.empty
    , doc = Just "Contains the StatefulApp type representing a stateful app."
    }
