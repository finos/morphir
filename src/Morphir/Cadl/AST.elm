module Morphir.Cadl.AST exposing (..)

-- expressions in cadl
-- alias string <> = expression ?? type ?? model
-- alias isValid = true
-- package = set of namespaces
-- namespace == modules

import Dict exposing (Dict)
import Set exposing (Set)


type alias Name =
    String


type alias Field =
    { name : Name
    , tpe : Type
    }



-- morphir equivalence to packages


type alias Namespace =
    Dict Name TypeDefinition



-- ways of defining types in CADL.
-- `ta` refers to typeAttribute or Additional Info that could be added to a type. An example
-- would be `template` defined on an alias type say; <K,V> in terms of dictionary.


type TypeDefinition
    = Alias Name Type


type Type
    = Boolean
    | String
