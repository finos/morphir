module Morphir.Type.SolutionMap exposing (..)

import Dict exposing (Dict)
import Morphir.Type.MetaType as MetaType exposing (MetaType)
import Morphir.Type.MetaVar exposing (Variable)


type SolutionMap
    = SolutionMap (Dict Variable MetaType)


empty : SolutionMap
empty =
    SolutionMap Dict.empty


isEmpty : SolutionMap -> Bool
isEmpty (SolutionMap solutions) =
    Dict.isEmpty solutions


singleton : Variable -> MetaType -> SolutionMap
singleton var metaType =
    SolutionMap (Dict.singleton var metaType)


fromList : List ( Variable, MetaType ) -> SolutionMap
fromList list =
    list
        |> Dict.fromList
        |> SolutionMap


get : Variable -> SolutionMap -> Maybe MetaType
get var (SolutionMap dict) =
    Dict.get var dict


substituteVariable : Variable -> MetaType -> SolutionMap -> SolutionMap
substituteVariable var replacement (SolutionMap solutions) =
    SolutionMap
        (solutions
            |> Dict.map
                (\_ metaType ->
                    metaType |> MetaType.substituteVariable var replacement
                )
        )
