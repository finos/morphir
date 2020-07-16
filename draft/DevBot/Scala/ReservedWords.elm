module SlateX.DevBot.Scala.ReservedWords exposing (..)


import Set exposing (Set)


reservedValueNames : Set String
reservedValueNames =
    Set.fromList
        -- we cannot use any method names in java.lamg.Object because values are represented as functions/values in a Scala object
        [ "clone", "equals", "finalize", "getClass", "hashCode", "notify", "notifyAll", "Debug.toString", "wait" 
        ]