module Morphir.Type.SolutionMap exposing (..)

import Dict exposing (Dict)
import Morphir.Type.MetaType as MetaType exposing (MetaType)


type SolutionMap
    = SolutionMap (Dict MetaType.Variable MetaType)


substitute : MetaType.Variable -> MetaType -> SolutionMap -> SolutionMap
substitute var replacement (SolutionMap dict) =
    SolutionMap
        (dict
            |> Dict.map
                (\_ metaType ->
                    metaType |> MetaType.substitute var replacement
                )
        )
