module Morphir.Value.Refactor exposing (inlineReferences, inlineVariables)

{-| Functions that transform a value expression without changing its semantics.


# Inlining

@docs inlineReferences, inlineVariables

-}

import Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Value as Value exposing (Value)


{-| Inline external references.
-}
inlineReferences : Dict FQName (Value ta va) -> Value ta va -> Value ta va
inlineReferences refs value =
    value
        |> Value.rewriteValue
            (\currentValue ->
                case currentValue of
                    Value.Reference _ fqn ->
                        refs |> Dict.get fqn

                    _ ->
                        Nothing
            )


{-| Inline variables.
-}
inlineVariables : Dict Name (Value ta va) -> Value ta va -> Value ta va
inlineVariables vars value =
    value
        |> Value.rewriteValue
            (\currentValue ->
                case currentValue of
                    Value.Variable _ name ->
                        vars |> Dict.get name

                    Value.LetDefinition _ boundName boundDef inValue ->
                        let
                            newVars : Dict Name (Value ta va)
                            newVars =
                                vars
                                    |> Dict.insert boundName
                                        (Value.definitionToValue boundDef)
                        in
                        Just (inlineVariables newVars inValue)

                    _ ->
                        Nothing
            )
