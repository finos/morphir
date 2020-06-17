module Morphir.IR.Type.Rewrite exposing (..)

import Morphir.IR.Type exposing (Field, Type(..))
import Morphir.Rewrite exposing (Rewrite)


rewriteType : Rewrite e (Type a)
rewriteType rewriteBranch rewriteLeaf typeToRewrite =
    case typeToRewrite of
        Reference a fQName argTypes ->
            argTypes
                |> List.foldr
                    (\nextArg resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch nextArg)
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map (Reference a fQName)

        Tuple a elemTypes ->
            elemTypes
                |> List.foldr
                    (\nextArg resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch nextArg)
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map (Tuple a)

        Record a fieldTypes ->
            fieldTypes
                |> List.foldr
                    (\field resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch field.tpe
                                |> Result.map (Field field.name)
                            )
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map (Record a)

        ExtensibleRecord a varName fieldTypes ->
            fieldTypes
                |> List.foldr
                    (\field resultSoFar ->
                        Result.map2 (::)
                            (rewriteBranch field.tpe
                                |> Result.map (Field field.name)
                            )
                            resultSoFar
                    )
                    (Ok [])
                |> Result.map (ExtensibleRecord a varName)

        Function a argType returnType ->
            Result.map2 (Function a)
                (rewriteBranch argType)
                (rewriteBranch returnType)

        _ ->
            rewriteLeaf typeToRewrite
