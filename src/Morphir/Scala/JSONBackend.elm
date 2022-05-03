module Morphir.Scala.JSONBackend exposing (..)

import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.Scala.AST as Scala exposing (MemberDecl(..))
import Morphir.Scala.Backend as ScalaBackend


type alias Error =
    String


mapTypeDefinition : FQName -> Type.Definition () -> Result Error (List Scala.MemberDecl)
mapTypeDefinition (( packageName, moduleName, typeName ) as fQTypeName) typeDef =
    case typeDef of
        Type.TypeAliasDefinition typeArgs typeExp ->
            let
                ( scalaTypePath, scalaName ) =
                    ScalaBackend.mapFQNameToPathAndName fQTypeName
            in
            genEncodeReference typeExp
                |> Result.map
                    (\encodeValue ->
                        [ ValueDecl
                            { modifiers = [ Scala.Implicit ]
                            , pattern = Scala.NamedMatch ("encode" :: typeName |> Name.toCamelCase)
                            , valueType =
                                Just
                                    (Scala.TypeApply
                                        (Scala.TypeRef [ "io", "circe" ] "Encoder")
                                        [ Scala.TypeRef scalaTypePath (scalaName |> Name.toTitleCase)
                                        ]
                                    )
                            , value =
                                encodeValue
                            }
                        ]
                    )

        Type.CustomTypeDefinition typeArgs accessControlledConstructors ->
            Debug.todo "implement"


genEncodeReference : Type () -> Result Error Scala.Value
genEncodeReference tpe =
    case tpe of
        Type.Variable _ varName ->
            Ok (Scala.Variable ("encode" :: varName |> Name.toCamelCase))

        Type.Reference _ ( packageName, moduleName, typeName ) typeArgs ->
            let
                scalaPackageName : List String
                scalaPackageName =
                    packageName ++ moduleName |> List.map (Name.toCamelCase >> String.toLower)

                scalaModuleName : String
                scalaModuleName =
                    "Codec"

                scalaReference : Scala.Value
                scalaReference =
                    Scala.Ref
                        (scalaPackageName ++ [ scalaModuleName ])
                        ("encode" :: typeName |> Name.toCamelCase)
            in
            Ok scalaReference

        Type.Tuple a types ->
            Debug.todo "implement"

        Type.Record a fields ->
            Debug.todo "implement"

        Type.ExtensibleRecord a name fields ->
            Debug.todo "implement"

        Type.Function a argType returnType ->
            Err "Cannot encode a function"

        Type.Unit a ->
            Debug.todo "implement"
