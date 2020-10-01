module Morphir.IR.Type.Instantiate exposing (..)

import AssocList as Dict exposing (Dict)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.Type as IR
import Morphir.IR.Type.Type as Infer


fromSrcType : Dict Name Infer.Type -> IR.Type ta -> Infer.Type
fromSrcType freeVars sourceType =
    case sourceType of
        IR.Function _ arg result ->
            Infer.FunN
                (fromSrcType freeVars arg)
                (fromSrcType freeVars result)

        IR.Variable _ name ->
            freeVars
                |> Dict.get name
                |> Maybe.withDefault Infer.never

        IR.Reference _ fQName args ->
            Infer.AppN fQName
                (args
                    |> List.map (fromSrcType freeVars)
                )

        --Can.TAlias home name args aliasedType ->
        --    do targs
        --        <- traverse (traverse (fromSrcType freeVars))
        --            args
        --            AliasN
        --            home
        --            name
        --            targs
        --        <$> (case aliasedType of
        --                Can.Filled realType ->
        --                    fromSrcType freeVars realType
        --
        --                Can.Holey realType ->
        --                    fromSrcType (Map.fromList targs) realType
        --            )
        IR.Tuple _ elemTypes ->
            Infer.TupleN
                (elemTypes
                    |> List.map
                        (\tpe ->
                            fromSrcType freeVars tpe
                        )
                )

        IR.Unit _ ->
            Infer.UnitN

        IR.Record _ fields ->
            Infer.RecordN
                (fields
                    |> List.map (fromSrcFieldType freeVars)
                    |> Dict.fromList
                )
                Infer.EmptyRecordN

        IR.ExtensibleRecord _ varName fields ->
            Infer.RecordN
                (fields
                    |> List.map (fromSrcFieldType freeVars)
                    |> Dict.fromList
                )
                (freeVars
                    |> Dict.get varName
                    |> Maybe.withDefault Infer.never
                )


fromSrcFieldType : Dict Name Infer.Type -> IR.Field ta -> ( Name, Infer.Type )
fromSrcFieldType freeVars field =
    ( field.name, fromSrcType freeVars field.tpe )
