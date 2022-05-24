module Morphir.Spark.Backend exposing (..)

{-| This module contains the Spark backend that takes a turns a Morphir IR into a Spark IR
-}

import Dict exposing (Dict)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR as IR exposing (IR)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue, Value)
import Morphir.SDK.ResultList as ResultList
import Morphir.Scala.AST as Scala
import Morphir.Scala.Backend as ScalaBackend
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.Scala.Spark.API as Spark
import Morphir.Spark.IR as SparkIR exposing (..)
import Set


type alias Options =
    {}


type Error
    = UnhandledValue TypedValue
    | UnknownValueReturnedByMapFunction TypedValue
    | FunctionNotFound FQName
    | UnknownArgumentType (Type ())
    | LambdaExpected TypedValue
    | MappingError SparkIR.Error


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            let
                ir : IR
                ir =
                    IR.fromDistribution distro
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


mapFunctionDefinition : IR -> FQName -> Result Error Scala.MemberDecl
mapFunctionDefinition ir (( _, _, localFunctionName ) as fullyQualifiedFunctionName) =
    let
        mapFunctionInputs : List ( Name, va, Type () ) -> Result Error (List Scala.ArgDecl)
        mapFunctionInputs inputTypes =
            inputTypes
                |> List.map
                    (\( argName, _, argType ) ->
                        case argType of
                            Type.Reference _ ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "list" ] ], [ "list" ] ) [ itemType ] ->
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

        mapFunctionBody : TypedValue -> Result Error Scala.Value
        mapFunctionBody body =
            body
                |> SparkIR.objectExpressionFromValue ir
                |> Result.mapError MappingError
                |> Result.andThen mapObjectExpressionToScala
    in
    ir
        |> IR.lookupValueDefinition fullyQualifiedFunctionName
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
                    (mapFunctionBody functionDef.body)
            )


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
                            |> mapFieldExpressions
                        )
                    )


mapExpression : Expression -> Scala.Value
mapExpression value =
    case value of
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

        Apply fQName argList ->
            Scala.Apply
                (toScalaRef fQName)
                (argList
                    |> List.map mapExpression
                    |> List.map (Scala.ArgValue Nothing)
                )


mapFieldExpressions : NamedExpressions -> List Scala.Value
mapFieldExpressions fieldExpressions =
    List.map
        (\( columnName, fieldExpression ) ->
            mapExpression fieldExpression
                |> Spark.alias (Name.toCamelCase columnName)
        )
        fieldExpressions


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


mapMorphirSDKFunctionToSpark : FQName -> Scala.Value
mapMorphirSDKFunctionToSpark fQName =
    let
        sparkFunctionsPath =
            [ "org", "apache", "spark", "sql", "functions" ]
    in
    case FQName.toString fQName of
        _ ->
            let
                ( path, n ) =
                    ScalaBackend.mapFQNameToPathAndName fQName
            in
            Scala.Ref path (ScalaBackend.mapValueName n)


mapMorphirValue : TypedValue -> Scala.Value
mapMorphirValue morphirValue =
    ScalaBackend.mapValue Set.empty morphirValue


toScalaRef : FQName -> Scala.Value
toScalaRef fQName =
    let
        ( path, name ) =
            ScalaBackend.mapFQNameToPathAndName fQName
    in
    Scala.Ref path (ScalaBackend.mapValueName name)
