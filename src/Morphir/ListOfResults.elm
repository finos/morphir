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


module Morphir.ListOfResults exposing (liftAllErrors, liftFirstError)


liftAllErrors : List (Result e a) -> Result (List e) (List a)
liftAllErrors results =
    let
        oks : List a
        oks =
            results
                |> List.filterMap
                    (\result ->
                        result
                            |> Result.toMaybe
                    )

        errs : List e
        errs =
            results
                |> List.filterMap
                    (\result ->
                        case result of
                            Ok _ ->
                                Nothing

                            Err e ->
                                Just e
                    )
    in
    case errs of
        [] ->
            Ok oks

        _ ->
            Err errs


liftFirstError : List (Result e a) -> Result e (List a)
liftFirstError results =
    case liftAllErrors results of
        Ok a ->
            Ok a

        Err errors ->
            errors
                |> List.head
                |> Maybe.map Err
                |> Maybe.withDefault (Ok [])
