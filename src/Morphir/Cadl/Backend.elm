module Morphir.Cadl.Backend exposing (..)

import Dict exposing (Dict)
import Morphir.Cadl.AST as AST exposing (ArrayType(..), Name, Namespace, NamespaceDeclaration, Type(..), TypeDefinition(..))
import Morphir.Cadl.PrettyPrinter as PrettyPrinter
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as IRName exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Type as IRType exposing (Type(..))
import Morphir.SDK.ResultList as ResultList


type alias Errors =
    List String


type alias Options =
    {}


mapDistribution : Options -> Distribution -> Result Errors FileMap
mapDistribution opt distro =
    case distro of
        Library packageName _ packageDef ->
            mapPackageDefinition packageDef
                |> Result.map (prettyPrint packageName)
                |> Result.map (Dict.singleton ( [], Path.toString IRName.toTitleCase "." packageName ++ ".cadl" ))


prettyPrint : PackageName -> Dict String NamespaceDeclaration -> String
prettyPrint packageName namespaces =
    namespaces
        |> Dict.toList
        |> List.map
            (\( namespaceName, namespace ) ->
                namespace
                    |> PrettyPrinter.mapNamespace namespaceName
            )
        |> String.concat


mapPackageDefinition : Package.Definition () (IRType.Type ()) -> Result Errors (Dict String NamespaceDeclaration)
mapPackageDefinition packageDef =
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( moduleName, accessControlledModDef ) ->
                accessControlledModDef.value
                    |> mapModuleDefinition
                    |> Result.map
                        (Tuple.pair
                            (Path.toString IRName.toTitleCase "." moduleName)
                        )
            )
        |> ResultList.keepFirstError
        |> Result.map Dict.fromList


mapModuleDefinition : Module.Definition () (IRType.Type ()) -> Result Errors NamespaceDeclaration
mapModuleDefinition definition =
    definition.types
        |> Dict.toList
        |> List.map
            (\( tpeName, accessControlledDoc ) ->
                accessControlledDoc.value.value
                    |> mapTypeDefinition tpeName
            )
        |> ResultList.keepFirstError
        |> Result.map Dict.fromList


mapTypeDefinition : IRName.Name -> IRType.Definition ta -> Result Errors ( AST.Name, TypeDefinition )
mapTypeDefinition tpeName definition =
    case definition of
        IRType.TypeAliasDefinition tpeArgs tpe ->
            tpe
                |> mapType
                |> Result.map
                    (\cadlType ->
                        case cadlType of
                            AST.Object fields ->
                                Model (tpeArgs |> List.map iRNameToName) fields
                                    |> Tuple.pair (iRNameToName tpeName)

                            _ ->
                                Alias (tpeArgs |> List.map iRNameToName) cadlType
                                    |> Tuple.pair (iRNameToName tpeName)
                    )

        IRType.CustomTypeDefinition tpeArgs accessControlled ->
            let
                isNoArgConstructors : Bool
                isNoArgConstructors =
                    accessControlled.value
                        |> Dict.toList
                        |> List.map Tuple.second
                        |> List.all List.isEmpty
            in
            if isNoArgConstructors then
                let
                    enumFields : AST.EnumValues
                    enumFields =
                        accessControlled.value
                            |> Dict.toList
                            |> List.map
                                (\( ctorName, _ ) ->
                                    iRNameToName ctorName
                                )
                in
                Ok
                    (Enum enumFields
                        |> Tuple.pair (iRNameToName tpeName)
                    )

            else
                let
                    unionTypeList : Result Errors (List AST.Type)
                    unionTypeList =
                        let
                            extractedTpe : IRType.ConstructorArgs a -> Result Errors (List AST.Type)
                            extractedTpe ctorArgs =
                                ctorArgs
                                    |> List.map (Tuple.second >> mapType)
                                    |> ResultList.keepFirstError
                        in
                        accessControlled.value
                            |> Dict.toList
                            |> List.map
                                (\( ctorName, ctorArgs ) ->
                                    if List.isEmpty ctorArgs then
                                        Ok (Const (iRNameToName ctorName))

                                    else
                                        extractedTpe ctorArgs
                                            |> Result.map
                                                (\lstOfTypesSoFar ->
                                                    Const (iRNameToName ctorName)
                                                        :: lstOfTypesSoFar
                                                        |> TupleType
                                                        |> Array
                                                )
                                )
                            |> ResultList.keepFirstError
                in
                unionTypeList
                    |> Result.map
                        (Union
                            >> Alias (tpeArgs |> List.map iRNameToName)
                            >> Tuple.pair (iRNameToName tpeName)
                        )


iRNameToName : IRName.Name -> AST.Name
iRNameToName name =
    IRName.toTitleCase name


mapType : IRType.Type ta -> Result Errors AST.Type
mapType tpe =
    case tpe of
        IRType.Reference _ (( packageName, moduleName, localName ) as fQName) argTypes ->
            case ( FQName.toString fQName, argTypes ) of
                ( "Morphir.SDK:Basics:bool", [] ) ->
                    Ok Boolean

                ( "Morphir.SDK:Basics:int", [] ) ->
                    Ok Integer

                ( "Morphir.SDK:Basics:float", [] ) ->
                    Ok Float

                ( "Morphir.SDK:String:string", [] ) ->
                    Ok String

                ( "Morphir.SDK:Char:char", [] ) ->
                    Ok String

                ( "Morphir.SDK:LocalDate:localDate", [] ) ->
                    Ok PlainDate

                ( "Morphir.SDK:LocalTime:localTime", [] ) ->
                    Ok PlainTime

                ( "Morphir.SDK:Decimal:decimal", [] ) ->
                    Ok String

                ( "Morphir.SDK:Month:month", [] ) ->
                    Ok String

                ( "Morphir.SDK:List:list", [ itemType ] ) ->
                    Result.map Array
                        (mapType itemType
                            |> Result.map ListType
                        )

                ( "Morphir.SDK:Set:set", [ itemType ] ) ->
                    Result.map Array
                        (mapType itemType
                            |> Result.map ListType
                        )

                ( "Morphir.SDK:Dict:dict", [ keyType, valueType ] ) ->
                    let
                        tupleList =
                            [ mapType keyType, mapType valueType ]
                    in
                    tupleList
                        |> ResultList.keepFirstError
                        |> Result.map (\tuple -> Array (ListType (Array (TupleType tuple))))

                ( "Morphir.SDK:Maybe:maybe", [ itemType ] ) ->
                    mapType itemType
                        |> Result.map
                            (\itemTyp ->
                                Union
                                    [ itemTyp
                                    , Null
                                    ]
                            )

                ( "Morphir.SDK:Result:result", [ error, value ] ) ->
                    [ mapType error
                        |> Result.map
                            (\err ->
                                Array (TupleType [ Const "Err", err ])
                            )
                    , mapType value
                        |> Result.map
                            (\val ->
                                Array (TupleType [ Const "Ok", val ])
                            )
                    ]
                        |> ResultList.keepFirstError
                        |> Result.map Union

                _ ->
                    argTypes
                        |> mapReferenceType packageName moduleName localName

        IRType.Variable _ nm ->
            Ok
                (AST.Variable (iRNameToName nm))

        IRType.Tuple _ typeList ->
            typeList
                |> List.map
                    (\typ ->
                        mapType typ
                    )
                |> ResultList.keepFirstError
                |> Result.map
                    (\itemType ->
                        Array (TupleType itemType)
                    )

        IRType.Record _ fields ->
            fields
                |> List.map
                    (\field ->
                        let
                            mapMandatoryType =
                                mapType field.tpe
                                    |> Result.map
                                        (\fieldType ->
                                            ( IRName.toCamelCase field.name, AST.FieldDef fieldType False )
                                        )
                        in
                        case field.tpe of
                            IRType.Reference _ fQName argTypes ->
                                case ( FQName.toString fQName, argTypes ) of
                                    ( "Morphir.SDK:Maybe:maybe", [ itemType ] ) ->
                                        mapType itemType
                                            |> Result.map
                                                (\fieldType ->
                                                    ( IRName.toCamelCase field.name, AST.FieldDef fieldType True )
                                                )

                                    _ ->
                                        mapMandatoryType

                            _ ->
                                mapMandatoryType
                    )
                |> ResultList.keepFirstError
                |> Result.map (Dict.fromList >> AST.Object)

        _ ->
            Err [ "Type " ++ Debug.toString tpe ++ " Not Supported" ]


mapReferenceType : PackageName -> ModuleName -> IRName.Name -> List (IRType.Type ta) -> Result Errors AST.Type
mapReferenceType packageName moduleName localName argTypes =
    let
        namespace : Namespace
        namespace =
            packageName
                ++ moduleName
                |> List.map IRName.toTitleCase

        name : AST.Name
        name =
            localName
                |> IRName.toTitleCase
    in
    argTypes
        |> List.map mapType
        |> ResultList.keepFirstError
        |> Result.map
            (\cadlArgTypes ->
                AST.Reference cadlArgTypes namespace name
            )
