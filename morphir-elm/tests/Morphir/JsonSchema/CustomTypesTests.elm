module Morphir.JsonSchema.CustomTypesTests exposing (..)

import Dict
import Expect
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Type as Type exposing (Definition(..), Type(..))
import Morphir.JsonSchema.AST exposing (ArrayType(..), SchemaType(..), StringConstraints)
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

        accessControlledTypeDefinition1 : Definition a
        accessControlledTypeDefinition1 =
            CustomTypeDefinition [ [ "Currencies" ] ] (AccessControlled Public (Dict.singleton [ "USD" ] []))

        accessControlledTypeDefinition2 =
            CustomTypeDefinition [ [ "Employee" ] ]
                (AccessControlled Public
                    (Dict.singleton [ "Fullname" ]
                        [ ( [], Type.Reference () ( [ [ "Morphir.SDK" ] ], [ [ "String" ] ], [ "string" ] ) [] )
                        ]
                    )
                )
    in
    describe "Tests for Custom Types"
        [ positiveTest "Test for Enum type"
            ( [ [ "CustomTypes" ] ], [ "Currencies" ] )
            accessControlledTypeDefinition1
            [ ( "CustomTypes.Currencies", OneOf [ Const "USD" ] ) ]
        , positiveTest "Test for custom type with single constructor"
            ( [ [ "CustomTypes" ] ], [ "Employee" ] )
            accessControlledTypeDefinition2
            [ ( "CustomTypes.Employee", OneOf [ Array (TupleType [ Const "Fullname", String (StringConstraints Nothing) ]) False ] ) ]
        ]
