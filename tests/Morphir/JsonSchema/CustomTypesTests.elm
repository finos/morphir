module Morphir.JsonSchema.CustomTypesTests exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Type exposing (Definition(..))
import Morphir.JsonSchema.AST exposing (SchemaType(..))
import Morphir.JsonSchema.Backend exposing (mapTypeDefinition)
import Test exposing (describe, test)


mapTypeDefinitionTests =
    let
        positiveTest name ( modulePath, moduleName ) accessControlledDocumentedTypeDef outputResult =
            test name
                (\_ ->
                    case mapTypeDefinition ( modulePath, moduleName ) accessControlledDocumentedTypeDef of
                        Ok output ->
                            output
                                |> Expect.equal outputResult

                        Err error ->
                            Expect.fail "Unable to map"
                )

        accessControlledTypeDef1 : Definition a
        accessControlledTypeDef1 =
            CustomTypeDefinition [ [ "Currencies" ] ] (AccessControlled Public (Dict.singleton [ "USD" ] []))
    in
    describe "Tests for Custom Types"
        [ positiveTest "Test for Enum type"
            ( [ [ "CustomTypes" ] ], [ "Currencies" ] )
            accessControlledTypeDef1
            [ ( "CustomTypes.Currencies", OneOf [ Const "USD" ] ) ]
        ]
