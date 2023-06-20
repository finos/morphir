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


module Morphir.Spark.Backend exposing (..)

{-| This module encapsulates the Spark backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated. The consumer is responsible for getting the input IR and saving the output
to the file-system.

This uses a two-step process

1.  Map value nodes to the Spark IR
2.  Map the Spark IR to scala value nodes.

@docs mapDistribution, mapFunctionDefinition, mapValue, mapObjectExpression, mapExpression, mapNamedExpression, mapLiteral, mapFQName

-}

import Dict exposing (Dict)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled as AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.Documented as Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue, Value)
import Morphir.SDK.ResultList as ResultList
import Morphir.Scala.AST as Scala
import Morphir.Scala.Common as ScalaBackend
import Morphir.Scala.Feature.Core as ScalaBackend
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.Spark.API as Spark
import Morphir.Spark.AST as SparkAST exposing (..)


type alias Options =
    {}


type Error
    = FunctionNotFound FQName
    | UnknownArgumentType (Type ())
    | MappingError SparkAST.Error


{-| Entry point for the Spark backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated.
-}
mapDistribution : Options -> Distribution -> FileMap
mapDistribution _ distro =
    let
        fixedDistro =
            fixDistribution distro
    in
    case fixedDistro of
        Distribution.Library packageName _ packageDef ->
            let
                ir : Distribution
                ir =
                    fixedDistro
            in
            packageDef.modules
                |> Dict.toList
                |> List.map
                    (\( moduleName, accessControlledModuleDef ) ->
                        let
                            packagePath : List String
                            packagePath =
                                packageName
                                    ++ moduleName
                                    |> List.map (Name.toCamelCase >> String.toLower)

                            object : Scala.TypeDecl
                            object =
                                Scala.Object
                                    { modifiers = []
                                    , name = "SparkJobs"
                                    , extends = []
                                    , members =
                                        accessControlledModuleDef.value.values
                                            |> Dict.toList
                                            |> List.filterMap
                                                (\( valueName, _ ) ->
                                                    case mapFunctionDefinition ir ( packageName, moduleName, valueName ) of
                                                        Ok memberDecl ->
                                                            Just (Scala.withoutAnnotation memberDecl)

                                                        Err err ->
                                                            let
                                                                _ =
                                                                    Debug.log "mapFunctionDefinition error" err
                                                            in
                                                            Nothing
                                                )
                                    , body = Nothing
                                    }

                            compilationUnit : Scala.CompilationUnit
                            compilationUnit =
                                { dirPath = packagePath
                                , fileName = "SparkJobs.scala"
                                , packageDecl = packagePath
                                , imports = []
                                , typeDecls = [ Scala.Documented Nothing (Scala.withoutAnnotation object) ]
                                }
                        in
                        ( ( packagePath, "SparkJobs.scala" )
                        , PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80) compilationUnit
                        )
                    )
                |> Dict.fromList


{-| Fix up the modules in the Distribution prior to generating Spark code
-}
fixDistribution : Distribution -> Distribution
fixDistribution distribution =
    case distribution of
        Distribution.Library libraryPackageName dependencies packageDef ->
            let
                updatedModules =
                    packageDef.modules
                        |> Dict.toList
                        |> List.map
                            (\( moduleName, accessControlledModuleDef ) ->
                                let
                                    updatedAccessControlledModuleDef =
                                        accessControlledModuleDef
                                            |> AccessControlled.map fixModuleDef
                                in
                                ( moduleName, updatedAccessControlledModuleDef )
                            )
                        |> Dict.fromList
            in
            Distribution.Library libraryPackageName dependencies { packageDef | modules = updatedModules }


{-| Fix up the values in a Module Definition prior to generating Spark code
-}
fixModuleDef : Module.Definition ta va -> Module.Definition ta va
fixModuleDef moduleDef =
    let
        updatedValues =
            moduleDef.values
                |> Dict.toList
                |> List.map
                    (\( valueName, accessControlledValueDef ) ->
                        let
                            updatedAccessControlledValueDef =
                                accessControlledValueDef
                                    |> AccessControlled.map
                                        (\documentedValueDef ->
                                            documentedValueDef
                                                |> Documented.map
                                                    (\valueDef ->
                                                        { valueDef | body = mapEnumToLiteral valueDef.body }
                                                    )
                                        )
                        in
                        ( valueName, updatedAccessControlledValueDef )
                    )
                |> Dict.fromList
    in
    { moduleDef | values = updatedValues }


{-| Replace no argument union constructors which correspond to enums, with string literals.
-}
mapEnumToLiteral : Value ta va -> Value ta va
mapEnumToLiteral value =
    value
        |> Value.rewriteValue
            (\currentValue ->
                case currentValue of
                    Value.Constructor va fqn ->
                        let
                            literal =
                                fqn
                                    |> FQName.getLocalName
                                    |> Name.toTitleCase
                                    |> StringLiteral
                                    |> Value.Literal va
                        in
                        Just literal

                    _ ->
                        Nothing
            )


{-| Maps function definitions defined within the current package to scala
-}
mapFunctionDefinition : Distribution -> FQName -> Result Error Scala.MemberDecl
mapFunctionDefinition ir (( _, _, localFunctionName ) as fullyQualifiedFunctionName) =
    let
        mapFunctionInputs : List ( Name, va, Type () ) -> Result Error (List Scala.ArgDecl)
        mapFunctionInputs inputTypes =
            inputTypes
                |> List.map
                    (\( argName, _, argType ) ->
                        case argType of
                            Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ _ ] ->
                                Ok
                                    { modifiers = []
                                    , tpe = Spark.dataFrame
                                    , name = Name.toCamelCase argName
                                    , defaultValue = Nothing
                                    }

                            other ->
                                Err (UnknownArgumentType other)
                    )
                |> ResultList.keepFirstError
    in
    ir
        |> Distribution.lookupValueDefinition fullyQualifiedFunctionName
        |> Result.fromMaybe (FunctionNotFound fullyQualifiedFunctionName)
        |> Result.andThen
            (\functionDef ->
                Result.map2
                    (\scalaArgs scalaFunctionBody ->
                        Scala.FunctionDecl
                            { modifiers = []
                            , name = localFunctionName |> Name.toCamelCase
                            , typeArgs = []
                            , args = [ scalaArgs ]
                            , returnType = Just Spark.dataFrame
                            , body = Just scalaFunctionBody
                            }
                    )
                    (mapFunctionInputs functionDef.inputTypes)
                    (mapValue ir functionDef.body)
            )


{-| Maps morphir values to scala values
-}
mapValue : Distribution -> TypedValue -> Result Error Scala.Value
mapValue ir body =
    body
        |> SparkAST.objectExpressionFromValue ir
        |> Result.mapError MappingError
        |> Result.andThen mapObjectExpressionToScala


{-| Maps Spark ObjectExpressions to scala values.
ObjectExpressions are defined as part of the SparkIR
-}
mapObjectExpressionToScala : ObjectExpression -> Result Error Scala.Value
mapObjectExpressionToScala objectExpression =
    case objectExpression of
        From name ->
            Name.toCamelCase name |> Scala.Variable |> Ok

        Filter predicate sourceRelation ->
            mapObjectExpressionToScala sourceRelation
                |> Result.map
                    (Spark.filter
                        (mapExpression predicate)
                    )

        Select fieldExpressions sourceRelation ->
            mapObjectExpressionToScala sourceRelation
                |> Result.map
                    (Spark.select
                        (fieldExpressions
                            |> mapNamedExpressions
                        )
                    )

        Aggregate groupfield fieldExpressions sourceRelation ->
            mapObjectExpressionToScala sourceRelation
                |> Result.map
                    (Spark.aggregate
                        groupfield
                        (mapNamedExpressions fieldExpressions)
                    )

        Join joinType baseRelation joinedRelation onClause ->
            let
                joinTypeName : String
                joinTypeName =
                    case joinType of
                        Inner ->
                            "inner"

                        Left ->
                            "left"
            in
            Result.map2
                (\baseDataFrame joinedDataFrame ->
                    Spark.join
                        baseDataFrame
                        (mapExpression onClause)
                        joinTypeName
                        joinedDataFrame
                )
                (mapObjectExpressionToScala baseRelation)
                (mapObjectExpressionToScala joinedRelation)


{-| Maps Spark Expressions to scala values.
Expressions are defined as part of the SparkIR.
-}
mapExpression : Expression -> Scala.Value
mapExpression expression =
    case expression of
        BinaryOperation simpleExpression leftExpr rightExpr ->
            Scala.BinOp
                (mapExpression leftExpr)
                simpleExpression
                (mapExpression rightExpr)

        Column colName ->
            Spark.column colName

        Literal literal ->
            mapLiteral literal |> Scala.Literal

        Variable name ->
            Scala.Variable name

        WhenOtherwise condition thenBranch elseBranch ->
            let
                toIfElseChain : Expression -> Scala.Value -> Scala.Value
                toIfElseChain v branchesSoFar =
                    case v of
                        WhenOtherwise cond nextThenBranch nextElseBranch ->
                            Spark.andWhen
                                (mapExpression cond)
                                (mapExpression nextThenBranch)
                                branchesSoFar
                                |> toIfElseChain nextElseBranch

                        _ ->
                            Spark.otherwise
                                (mapExpression v)
                                branchesSoFar
            in
            Spark.when
                (mapExpression condition)
                (mapExpression thenBranch)
                |> toIfElseChain elseBranch

        Method target name argList ->
            Scala.Apply
                (Scala.Select (mapExpression target) name)
                (argList
                    |> List.map mapExpression
                    |> List.map (Scala.ArgValue Nothing)
                )

        Function name argList ->
            Scala.Apply
                (Scala.Ref [ "org", "apache", "spark", "sql", "functions" ] name)
                (argList
                    |> List.map mapExpression
                    |> List.map (Scala.ArgValue Nothing)
                )


{-| Maps NamedExpressions to scala values.
-}
mapNamedExpressions : NamedExpressions -> List Scala.Value
mapNamedExpressions nameExpressions =
    List.map
        (\( columnName, named ) ->
            mapExpression named
                |> Spark.alias (Name.toCamelCase columnName)
        )
        nameExpressions


{-| Maps Spark Literals to scala Literals.
-}
mapLiteral : Literal -> Scala.Lit
mapLiteral l =
    case l of
        BoolLiteral bool ->
            Scala.BooleanLit bool

        CharLiteral char ->
            Scala.CharacterLit char

        StringLiteral string ->
            Scala.StringLit string

        WholeNumberLiteral int ->
            Scala.IntegerLit int

        FloatLiteral float ->
            Scala.FloatLit float

        DecimalLiteral _ ->
            Debug.todo "branch 'DecimalLiteral _' not implemented"


{-| Maps a fully qualified name to scala Ref value.
-}
mapFQName : FQName -> Scala.Value
mapFQName fQName =
    let
        ( path, name ) =
            ScalaBackend.mapFQNameToPathAndName fQName
    in
    Scala.Ref path (ScalaBackend.mapValueName name)
