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
