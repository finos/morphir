module Morphir.IR.Type.InferTests exposing (..)

import AssocList as Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName, fQName)
import Morphir.IR.Literal as Literal
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)


type alias Scenario =
    { vars : Dict Name (Type ())
    , vals : Dict FQName (Type ())
    , inferred : Value () (Type ())
    }


scenarios : List Scenario
scenarios =
    [ { vars = Dict.empty
      , vals = Dict.empty
      , inferred =
            Value.Literal (Type.Reference () (fqn "Morphir.SDK" "String" "String") [])
                (Literal.StringLiteral "foo")
      }
    , { vars =
            Dict.fromList
                [ ( [ "a" ], Type.Reference () (fqn "Morphir.SDK" "String" "String") [] )
                ]
      , vals = Dict.empty
      , inferred =
            Value.Variable (Type.Reference () (fqn "Morphir.SDK" "String" "String") [])
                [ "a" ]
      }
    ]


fqn : String -> String -> String -> FQName
fqn packageName moduleName localName =
    fQName
        (Path.fromString packageName)
        (Path.fromString moduleName)
        (Name.fromString localName)
