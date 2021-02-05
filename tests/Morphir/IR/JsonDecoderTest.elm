module Morphir.IR.JsonDecoderTest exposing (..)

import Expect
import Json.Decode as Decode
import Morphir.IR.DataCodec exposing (decodeData)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Value)
import Test exposing (Test, describe, test)


decodeDataTest : Test
decodeDataTest =
    let
        intDecoder : Type ()
        intDecoder =
            Type.Reference () (fqn "Morphir.SDK" "Basics" "Int") []

        floatDecoder : Type ()
        floatDecoder =
            Type.Reference () (fqn "Morphir.SDK" "Basics" "Float") []

        charDecoder : Type ()
        charDecoder =
            Type.Reference () (fqn "Morphir.SDK" "Char" "Char") []

        stringDecoder : Type ()
        stringDecoder =
            Type.Reference () (fqn "Morphir.SDK" "String" "String") []
    in
    describe "JsonDecoderTest"
        [ test "PassedInt"
            (\_ ->
                case decodeData intDecoder of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "42") (Ok (Value.literal () (IntLiteral 42)))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "PassedFloat"
            (\_ ->
                case decodeData floatDecoder of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "42.5") (Ok (Value.literal () (FloatLiteral 42.5)))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "PassedChar"
            (\_ ->
                case decodeData charDecoder of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "\"a\"") (Ok (Value.literal () (StringLiteral "a")))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        , test "PassedString"
            (\_ ->
                case decodeData stringDecoder of
                    Ok decoder ->
                        Expect.equal (Decode.decodeString decoder "\"Hello\"") (Ok (Value.literal () (StringLiteral "Hello")))

                    Err error ->
                        Expect.equal "Cannot Decode this type" error
            )
        ]
