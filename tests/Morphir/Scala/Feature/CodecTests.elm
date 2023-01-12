module Morphir.Scala.Feature.CodecTests exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (fqn)
import Morphir.IR.Type as Type exposing (Definition(..), Type)
import Morphir.Scala.AST as Scala exposing (ArgValue(..), Generator(..), Lit(..), Pattern(..), Value(..))
import Morphir.Scala.Feature.Codec exposing (mapTypeDefinitionToEncoder, mapTypeToDecoderReference, mapTypeToEncoderReference)
import Test exposing (Test, describe, test)


mapTypeToEncoderReferenceTests : Test
mapTypeToEncoderReferenceTests =
    let
        positiveTest name tpeName tpePath typeParams tpe expectedOutput =
            test name
                (\_ ->
                    case mapTypeToEncoderReference tpeName tpePath typeParams tpe of
                        Ok output ->
                            output
                                |> Expect.equal expectedOutput

                        Err error ->
                            Expect.fail error
                )
    in
    describe "Generate Encoder Reference Tests"
        [ positiveTest "1. Type Variable "
            []
            []
            [ [] ]
            (Type.Variable () [ "foo" ])
            (Scala.Variable "encodeFoo")
        , positiveTest "2. Type Reference"
            []
            []
            [ [] ]
            (Type.Reference () (fqn "morphir" "sdk" "string") [])
            (Scala.Ref [ "morphir", "sdk", "Codec" ] "encodeString")
        ]
