module Morphir.Elm.Frontend.ResolveTests exposing (..)

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

import Dict
import Elm.Syntax.Exposing exposing (ExposedType, Exposing(..), TopLevelExpose(..))
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.Node exposing (Node(..))
import Elm.Syntax.Range exposing (emptyRange)
import Expect
import Morphir.Elm.Frontend exposing (defaultDependencies)
import Morphir.Elm.Frontend.Resolve exposing (Error(..), ImportedNames, LocalNames, ModuleResolver, collectImportedNames, createModuleResolver)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName exposing (FQName, fQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module
import Morphir.IR.Package as Package
import Morphir.IR.Path exposing (Path)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value
import Test exposing (Test, describe, test)


moduleResolverTests : Test
moduleResolverTests =
    let
        otherPackage : Package.Specification ()
        otherPackage =
            Package.Specification
                (Dict.fromList
                    [ ( [ [ "module", "1" ] ]
                      , { types =
                            Dict.fromList
                                [ ( [ "one" ], Documented "" (Type.CustomTypeSpecification [] (Dict.fromList [ ( [ "one" ], [] ) ])) )
                                , ( [ "one", "one" ], Documented "" (Type.CustomTypeSpecification [] (Dict.fromList [ ( [ "one", "two" ], [] ) ])) )
                                , ( [ "rec", "one" ], Documented "" (Type.TypeAliasSpecification [] (Type.Record () [])) )
                                ]
                        , values =
                            Dict.fromList
                                [ ( [ "one" ], Documented "" (Value.Specification [] (Basics.intType ())) )
                                ]
                        , doc = Just "module1"
                        }
                      )
                    , ( [ [ "module", "2" ] ]
                      , { types =
                            Dict.fromList
                                [ ( [ "two" ], Documented "" (Type.CustomTypeSpecification [] (Dict.fromList [ ( [ "two", "one" ], [] ) ])) )
                                , ( [ "rec", "two" ], Documented "" (Type.TypeAliasSpecification [] (Type.Record () [])) )
                                ]
                        , values =
                            Dict.fromList
                                [ ( [ "two" ], Documented "" (Value.Specification [] (Basics.intType ())) )
                                ]
                        , doc = Just "module2"
                        }
                      )
                    , ( [ [ "module", "3" ] ]
                      , { types =
                            Dict.fromList
                                [ ( [ "three" ], Documented "" (Type.CustomTypeSpecification [] (Dict.fromList [ ( [ "three", "four" ], [] ) ])) )
                                , ( [ "rec", "three" ], Documented "" (Type.TypeAliasSpecification [] (Type.Record () [])) )
                                ]
                        , values =
                            Dict.fromList
                                [ ( [ "three" ], Documented ""( Value.Specification [] (Basics.intType ())) )
                                ]
                        , doc = Just "module3"
                        }
                      )
                    ]
                )

        moduleResolver : ModuleResolver
        moduleResolver =
            createModuleResolver
                { dependencies =
                    Dict.union
                        defaultDependencies
                        (Dict.singleton [ [ "other" ] ] otherPackage)
                , currentPackagePath =
                    [ [ "test" ] ]
                , currentPackageModules =
                    Dict.empty
                , explicitImports =
                    [ Import (Node emptyRange [ "Other", "Module1" ])
                        Nothing
                        (Just
                            (Node emptyRange
                                (Explicit
                                    [ Node emptyRange (TypeOrAliasExpose "One")
                                    , Node emptyRange (TypeExpose (ExposedType "OneOne" (Just emptyRange)))
                                    , Node emptyRange (TypeOrAliasExpose "RecOne")
                                    , Node emptyRange (FunctionExpose "one")
                                    ]
                                )
                            )
                        )
                    , Import (Node emptyRange [ "Other", "Module2" ])
                        Nothing
                        (Just (Node emptyRange (All emptyRange)))
                    , Import (Node emptyRange [ "Other", "Module3" ])
                        (Just (Node emptyRange [ "MyModule3" ]))
                        Nothing
                    ]
                , currentModulePath =
                    [ [ "module" ] ]
                , moduleDef =
                    Module.Definition
                        (Dict.fromList
                            [ ( [ "zero" ], AccessControlled Private (Documented "" (Type.CustomTypeDefinition [] (AccessControlled Private (Dict.fromList [ ( [ "zero", "one" ], [] ) ])))) )
                            , ( [ "rec", "zero" ], AccessControlled Private (Documented "" (Type.TypeAliasDefinition [] (Type.Record () []))) )
                            ]
                        )
                        (Dict.fromList
                            [ ( [ "zero" ], AccessControlled Private ( Documented "" (Value.Definition [] (Basics.intType ()) (Value.Literal () (WholeNumberLiteral 42)))) )
                            ]
                        )
                        Nothing
                }

        assert : String -> (List String -> String -> Result Error FQName) -> List String -> String -> FQName -> Test
        assert testName resolve moduleName localName expectedFQName =
            test testName <|
                \_ ->
                    resolve moduleName localName
                        |> Expect.equal (Ok expectedFQName)
    in
    describe "moduleResolver"
        [ assert "Resolve type name defined locally"
            moduleResolver.resolveType
            []
            "Zero"
            (fQName [ [ "test" ] ] [ [ "module" ] ] [ "zero" ])
        , assert "Resolve type name imported explicitly"
            moduleResolver.resolveType
            []
            "One"
            (fQName [ [ "other" ] ] [ [ "module", "1" ] ] [ "one" ])
        , assert "Resolve type name imported using open import"
            moduleResolver.resolveType
            []
            "Two"
            (fQName [ [ "other" ] ] [ [ "module", "2" ] ] [ "two" ])
        , assert "Resolve type name with full module name"
            moduleResolver.resolveType
            [ "Other", "Module3" ]
            "Three"
            (fQName [ [ "other" ] ] [ [ "module", "3" ] ] [ "three" ])
        , assert "Resolve type name with alias"
            moduleResolver.resolveType
            [ "MyModule3" ]
            "Three"
            (fQName [ [ "other" ] ] [ [ "module", "3" ] ] [ "three" ])
        , assert "Resolve ctor name defined locally"
            moduleResolver.resolveCtor
            []
            "ZeroOne"
            (fQName [ [ "test" ] ] [ [ "module" ] ] [ "zero", "one" ])
        , assert "Resolve ctor name imported explicitly"
            moduleResolver.resolveCtor
            []
            "OneTwo"
            (fQName [ [ "other" ] ] [ [ "module", "1" ] ] [ "one", "two" ])
        , assert "Resolve ctor name imported using open import"
            moduleResolver.resolveCtor
            []
            "TwoOne"
            (fQName [ [ "other" ] ] [ [ "module", "2" ] ] [ "two", "one" ])
        , assert "Resolve ctor name with full module name"
            moduleResolver.resolveCtor
            [ "Other", "Module3" ]
            "ThreeFour"
            (fQName [ [ "other" ] ] [ [ "module", "3" ] ] [ "three", "four" ])
        , assert "Resolve ctor name with alias"
            moduleResolver.resolveCtor
            [ "MyModule3" ]
            "ThreeFour"
            (fQName [ [ "other" ] ] [ [ "module", "3" ] ] [ "three", "four" ])
        , assert "Resolve value name defined locally"
            moduleResolver.resolveValue
            []
            "zero"
            (fQName [ [ "test" ] ] [ [ "module" ] ] [ "zero" ])
        , assert "Resolve value name imported explicitly"
            moduleResolver.resolveValue
            []
            "one"
            (fQName [ [ "other" ] ] [ [ "module", "1" ] ] [ "one" ])
        , assert "Resolve value name imported using open import"
            moduleResolver.resolveValue
            []
            "two"
            (fQName [ [ "other" ] ] [ [ "module", "2" ] ] [ "two" ])
        , assert "Resolve value name with full module name"
            moduleResolver.resolveValue
            [ "Other", "Module3" ]
            "three"
            (fQName [ [ "other" ] ] [ [ "module", "3" ] ] [ "three" ])
        , assert "Resolve value name with alias"
            moduleResolver.resolveValue
            [ "MyModule3" ]
            "three"
            (fQName [ [ "other" ] ] [ [ "module", "3" ] ] [ "three" ])
        , assert "Resolve record ctor name defined locally"
            moduleResolver.resolveCtor
            []
            "RecZero"
            (fQName [ [ "test" ] ] [ [ "module" ] ] [ "rec", "zero" ])
        , assert "Resolve record ctor name imported explicitly"
            moduleResolver.resolveCtor
            []
            "RecOne"
            (fQName [ [ "other" ] ] [ [ "module", "1" ] ] [ "rec", "one" ])
        , assert "Resolve record ctor name imported using open import"
            moduleResolver.resolveCtor
            []
            "RecTwo"
            (fQName [ [ "other" ] ] [ [ "module", "2" ] ] [ "rec", "two" ])
        , assert "Resolve record ctor name with full module name"
            moduleResolver.resolveCtor
            [ "Other", "Module3" ]
            "RecThree"
            (fQName [ [ "other" ] ] [ [ "module", "3" ] ] [ "rec", "three" ])
        , assert "Resolve record ctor name with alias"
            moduleResolver.resolveCtor
            [ "MyModule3" ]
            "RecThree"
            (fQName [ [ "other" ] ] [ [ "module", "3" ] ] [ "rec", "three" ])
        ]


collectImportedNamesTests : Test
collectImportedNamesTests =
    let
        -- This is a mock to simulate looking up other modules in the package or in its dependencies
        getModulesExposedNames : Path -> Result Error ( Path, Path, LocalNames )
        getModulesExposedNames moduleName =
            case moduleName of
                [ [ "foo" ], [ "bar" ] ] ->
                    Ok
                        ( [ [ "foo" ] ]
                        , [ [ "bar" ] ]
                        , LocalNames
                            [ [ "baz" ], [ "bat" ] ]
                            Dict.empty
                            [ [ "ugh" ] ]
                        )

                [ [ "other" ], [ "module" ] ] ->
                    Ok
                        ( [ [ "other" ] ]
                        , [ [ "module" ] ]
                        , LocalNames
                            [ [ "one" ], [ "bat" ] ]
                            (Dict.fromList
                                [ ( [ "one" ], [ [ "two" ], [ "three" ] ] )
                                ]
                            )
                            [ [ "ugh" ], [ "yeah" ] ]
                        )

                _ ->
                    Err (CouldNotFindModule moduleName)

        fooBarModulePath : ( Path, Path )
        fooBarModulePath =
            ( [ [ "foo" ] ], [ [ "bar" ] ] )

        otherModulePath : ( Path, Path )
        otherModulePath =
            ( [ [ "other" ] ], [ [ "module" ] ] )

        assert : String -> List Import -> ImportedNames -> Test
        assert testName imports expectedNames =
            test testName <|
                \_ ->
                    collectImportedNames getModulesExposedNames imports
                        |> Expect.equal (Ok expectedNames)
    in
    describe "collectImportedNames"
        [ assert "No imports returns no names"
            []
            (ImportedNames Dict.empty Dict.empty Dict.empty)
        , assert "Single import is decomposed correctly"
            [ Import (Node emptyRange [ "Foo", "Bar" ])
                Nothing
                (Just
                    (Node emptyRange
                        (Explicit
                            [ Node emptyRange (TypeOrAliasExpose "Baz")
                            , Node emptyRange (TypeExpose (ExposedType "Bat" Nothing))
                            , Node emptyRange (FunctionExpose "ugh")
                            ]
                        )
                    )
                )
            ]
            (ImportedNames
                (Dict.fromList
                    [ ( [ "baz" ], [ fooBarModulePath ] )
                    , ( [ "bat" ], [ fooBarModulePath ] )
                    ]
                )
                Dict.empty
                (Dict.fromList
                    [ ( [ "ugh" ], [ fooBarModulePath ] )
                    ]
                )
            )
        , assert "Multiple imports are decomposed and merged correctly"
            [ Import (Node emptyRange [ "Foo", "Bar" ])
                Nothing
                (Just
                    (Node emptyRange
                        (Explicit
                            [ Node emptyRange (TypeOrAliasExpose "Baz")
                            , Node emptyRange (TypeExpose (ExposedType "Bat" Nothing))
                            , Node emptyRange (FunctionExpose "ugh")
                            ]
                        )
                    )
                )
            , Import (Node emptyRange [ "Other", "Module" ])
                Nothing
                (Just
                    (Node emptyRange
                        (Explicit
                            [ Node emptyRange (TypeOrAliasExpose "One")
                            , Node emptyRange (TypeExpose (ExposedType "Bat" Nothing))
                            , Node emptyRange (FunctionExpose "ugh")
                            , Node emptyRange (FunctionExpose "yeah")
                            ]
                        )
                    )
                )
            ]
            (ImportedNames
                (Dict.fromList
                    [ ( [ "baz" ], [ fooBarModulePath ] )
                    , ( [ "bat" ], [ fooBarModulePath, otherModulePath ] )
                    , ( [ "one" ], [ otherModulePath ] )
                    ]
                )
                Dict.empty
                (Dict.fromList
                    [ ( [ "ugh" ], [ fooBarModulePath, otherModulePath ] )
                    , ( [ "yeah" ], [ otherModulePath ] )
                    ]
                )
            )
        , assert "Top level open imports are decomposed and merged correctly"
            [ Import (Node emptyRange [ "Foo", "Bar" ])
                Nothing
                (Just
                    (Node emptyRange
                        (Explicit
                            [ Node emptyRange (TypeOrAliasExpose "Baz")
                            , Node emptyRange (TypeExpose (ExposedType "Bat" Nothing))
                            , Node emptyRange (FunctionExpose "ugh")
                            ]
                        )
                    )
                )
            , Import (Node emptyRange [ "Other", "Module" ])
                Nothing
                (Just (Node emptyRange (All emptyRange)))
            ]
            (ImportedNames
                (Dict.fromList
                    [ ( [ "baz" ], [ fooBarModulePath ] )
                    , ( [ "bat" ], [ fooBarModulePath, otherModulePath ] )
                    , ( [ "one" ], [ otherModulePath ] )
                    ]
                )
                (Dict.fromList
                    [ ( [ "two" ], [ otherModulePath ] )
                    , ( [ "three" ], [ otherModulePath ] )
                    ]
                )
                (Dict.fromList
                    [ ( [ "ugh" ], [ fooBarModulePath, otherModulePath ] )
                    , ( [ "yeah" ], [ otherModulePath ] )
                    ]
                )
            )
        , assert "Type level open imports are decomposed and merged correctly"
            [ Import (Node emptyRange [ "Foo", "Bar" ])
                Nothing
                (Just
                    (Node emptyRange
                        (Explicit
                            [ Node emptyRange (TypeOrAliasExpose "Baz")
                            , Node emptyRange (TypeExpose (ExposedType "Bat" Nothing))
                            , Node emptyRange (FunctionExpose "ugh")
                            ]
                        )
                    )
                )
            , Import (Node emptyRange [ "Other", "Module" ])
                Nothing
                (Just
                    (Node emptyRange
                        (Explicit
                            [ Node emptyRange (TypeExpose (ExposedType "One" (Just emptyRange)))
                            ]
                        )
                    )
                )
            ]
            (ImportedNames
                (Dict.fromList
                    [ ( [ "baz" ], [ fooBarModulePath ] )
                    , ( [ "bat" ], [ fooBarModulePath ] )
                    , ( [ "one" ], [ otherModulePath ] )
                    ]
                )
                (Dict.fromList
                    [ ( [ "two" ], [ otherModulePath ] )
                    , ( [ "three" ], [ otherModulePath ] )
                    ]
                )
                (Dict.fromList
                    [ ( [ "ugh" ], [ fooBarModulePath ] )
                    ]
                )
            )
        ]
