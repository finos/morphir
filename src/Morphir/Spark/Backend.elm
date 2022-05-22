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
                        (mapFieldExpression predicate)
                    )

        Select fieldExpressions sourceRelation ->
            mapObjectExpressionToScala sourceRelation
                |> Result.map
                    (Spark.select
                        (fieldExpressions
                            |> mapFieldExpressions
                        )
                    )


mapFieldExpression : FieldExpression -> Scala.Value
mapFieldExpression value =
    let
        default v =
            ScalaBackend.mapValue Set.empty v

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
    in
    case value of
        SparkIR.Lit lit ->
            Spark.literal (Scala.Literal (mapLiteral lit))

        SparkIR.Col name ->
            Spark.column (Name.toCamelCase name)

        SparkIR.ColumExpression fqn arg1 arg2 ->
            case FQName.toString fqn of
                "Morphir.SDK:Basics:equal" ->
                    Scala.BinOp (mapFieldExpression arg1) "===" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:notEqual" ->
                    Scala.BinOp (mapFieldExpression arg1) "=!=" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:add" ->
                    Scala.BinOp (mapFieldExpression arg1) "+" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:subtract" ->
                    Scala.BinOp (mapFieldExpression arg1) "-" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:multiply" ->
                    Scala.BinOp (mapFieldExpression arg1) "*" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:divide" ->
                    Scala.BinOp (mapFieldExpression arg1) "/" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:power" ->
                    Scala.BinOp (mapFieldExpression arg1) "pow" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:modBy" ->
                    Scala.BinOp (mapFieldExpression arg1) "mod" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:remainderBy" ->
                    Scala.BinOp (mapFieldExpression arg1) "%" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:logBase" ->
                    Scala.BinOp (mapFieldExpression arg1) "log" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:atan2" ->
                    Scala.BinOp (mapFieldExpression arg1) "atan2" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:lessThan" ->
                    Scala.BinOp (mapFieldExpression arg1) "<" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:greaterThan" ->
                    Scala.BinOp (mapFieldExpression arg1) ">" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:lessThanOrEqual" ->
                    Scala.BinOp (mapFieldExpression arg1) "<=" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:greaterThanOrEqual" ->
                    Scala.BinOp (mapFieldExpression arg1) ">=" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:max" ->
                    Scala.BinOp (mapFieldExpression arg1) "max" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:min" ->
                    Scala.BinOp (mapFieldExpression arg1) "min" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:and" ->
                    Scala.BinOp (mapFieldExpression arg1) "and" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:or" ->
                    Scala.BinOp (mapFieldExpression arg1) "or" (mapFieldExpression arg2)

                "Morphir.SDK:Basics:xor" ->
                    Scala.BinOp (mapFieldExpression arg1) "xor" (mapFieldExpression arg2)

                _ ->
                    default (Value.Unit (Type.Unit ()))

        SparkIR.WhenOtherwise cond thenBranch elseBranch ->
            Spark.when
                (mapFieldExpression cond)
                (mapFieldExpression thenBranch)
                |> Spark.otherwise (mapFieldExpression elseBranch)

        SparkIR.Transform colName morphirValue ->
            Spark.transform
                (mapFieldExpression colName)
                (mapFieldExpression morphirValue)

        SparkIR.Lambda args body ->
            Scala.Lambda
                (List.map (\name -> ( Name.toCamelCase name, Nothing )) args)
                (default body)

        Native fQName ->
            mapNativeExpression fQName

        SparkIR.GenericExpression v ->
            default v


mapFieldExpressions : FieldExpressions -> List Scala.Value
mapFieldExpressions fieldExpressions =
    List.map
        (\( columnName, fieldExpression ) ->
            mapFieldExpression fieldExpression
                |> Spark.alias (Name.toCamelCase columnName)
        )
        fieldExpressions


mapNativeExpression : FQName -> Scala.Value
mapNativeExpression fQName =
    case FQName.toString fQName of
        "Morphir.SDK:String:Upper" ->
            Debug.todo ""

        fqn ->
            let
                _ =
                    Debug.log "Unable to map FQName" fqn
            in
            ScalaBackend.mapValue Set.empty (Value.Unit (Type.Unit ()))
