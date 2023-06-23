module Morphir.Scala.Spark.Backend exposing (..)

import Dict exposing (Dict)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (TypedValue, Value)
import Morphir.Relational.Backend as RelationalBackend
import Morphir.Relational.IR exposing (JoinType(..), OuterJoinType(..), Relation(..))
import Morphir.SDK.ResultList as ResultList
import Morphir.Scala.AST as Scala
import Morphir.Scala.Feature.Core exposing (mapValue)
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.Spark.API as Spark
import Set


type alias Options =
    {}


type Error
    = FunctionNotFound FQName
    | RelationalBackendError RelationalBackend.Error
    | UnknownArgumentType (Type ())
    | LambdaExpected TypedValue


mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
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
                                                    case mapFunctionDefinition distro ( packageName, moduleName, valueName ) of
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


mapFunctionDefinition : Distribution -> FQName -> Result Error Scala.MemberDecl
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
                |> RelationalBackend.mapFunctionBody
                |> Result.mapError RelationalBackendError
                |> Result.andThen mapRelation
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
                    (mapFunctionBody functionDef.body)
            )


mapRelation : Relation -> Result Error Scala.Value
mapRelation relation =
    case relation of
        Values values ->
            Debug.todo "not implemented yet"

        From name ->
            Ok (Scala.Variable (Name.toCamelCase name))

        Where predicate sourceRelation ->
            case predicate of
                Value.Lambda _ _ body ->
                    mapRelation sourceRelation
                        |> Result.map
                            (Spark.filter
                                (mapColumnExpression body)
                            )

                _ ->
                    Err (LambdaExpected predicate)

        Select columns sourceRelation ->
            mapRelation sourceRelation
                |> Result.map
                    (Spark.select
                        (columns
                            |> List.map
                                (\( columnName, columnValue ) ->
                                    mapColumnExpression columnValue
                                        |> Spark.alias (Name.toCamelCase columnName)
                                )
                        )
                    )

        Join joinType predicate leftRelation rightRelation ->
            Result.map2
                (\left right ->
                    Spark.join right
                        (mapColumnExpression predicate)
                        (case joinType of
                            Inner ->
                                "inner"

                            Outer Left ->
                                "left"

                            Outer Right ->
                                "right"

                            Outer Full ->
                                "full"
                        )
                        left
                )
                (mapRelation leftRelation)
                (mapRelation rightRelation)


mapColumnExpression : TypedValue -> Scala.Value
mapColumnExpression value =
    let
        default v =
            mapValue Set.empty v

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

                DecimalLiteral decimal ->
                    Scala.DecimalLit decimal
    in
    case value of
        Value.Literal _ lit ->
            Spark.literal (Scala.Literal (mapLiteral lit))

        Value.Field _ _ name ->
            Spark.column (Name.toCamelCase name)

        Value.Apply _ (Value.Apply _ (Value.Reference _ fqn) arg1) arg2 ->
            case FQName.toString fqn of
                "Morphir.SDK:Basics:equal" ->
                    Scala.BinOp (mapColumnExpression arg1) "===" (mapColumnExpression arg2)

                _ ->
                    default value

        Value.IfThenElse _ _ _ _ ->
            let
                toIfElseChain : TypedValue -> ( List ( TypedValue, TypedValue ), TypedValue )
                toIfElseChain v =
                    case v of
                        Value.IfThenElse _ cond thenBranch elseBranch ->
                            let
                                ( nestedCases, otherwise ) =
                                    toIfElseChain elseBranch
                            in
                            ( ( cond, thenBranch ) :: nestedCases, otherwise )

                        _ ->
                            ( [], v )

                toScala : ( List ( TypedValue, TypedValue ), TypedValue ) -> Scala.Value -> Scala.Value
                toScala ( cases, otherwise ) soFar =
                    case cases of
                        [] ->
                            Spark.otherwise (mapColumnExpression otherwise) soFar

                        ( headCond, headBranch ) :: tailCases ->
                            toScala ( tailCases, otherwise )
                                (Spark.andWhen
                                    (mapColumnExpression headCond)
                                    (mapColumnExpression headBranch)
                                    soFar
                                )
            in
            case value |> toIfElseChain of
                ( [], otherwise ) ->
                    mapColumnExpression otherwise

                ( ( firstCond, firstBranch ) :: otherCases, otherwise ) ->
                    toScala ( otherCases, otherwise )
                        (Spark.when
                            (mapColumnExpression firstCond)
                            (mapColumnExpression firstBranch)
                        )

        _ ->
            default value
