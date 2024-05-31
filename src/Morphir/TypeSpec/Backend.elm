module Morphir.TypeSpec.Backend exposing (..)

import Dict exposing (Dict)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as IRName exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path
import Morphir.IR.Repo as Distribution
import Morphir.IR.Type as IRType exposing (Specification(..), Type(..))
import Morphir.SDK.ResultList as ResultList
import Morphir.TypeSpec.AST as AST exposing (ArrayType(..), ImportDeclaration(..), Name, Namespace, NamespaceDeclaration, ScalarType(..), Type(..), TypeDefinition(..))
import Morphir.TypeSpec.PrettyPrinter as PrettyPrinter
import Set exposing (Set)


type alias Errors =
    List String


type alias Options =
    {}


morphirTypeSpecSDK =
    "@morphir/typespec-sdk"


mapDistribution : Options -> Distribution -> Result Errors FileMap
mapDistribution opt distro =
    case distro of
        Library packageName _ packageDef ->
            let
                shouldImportSDK : Bool
                shouldImportSDK =
                    packageDef.modules
                        |> Dict.toList
                        |> List.map (Tuple.second >> .value >> Module.collectTypeReferences)
                        |> List.foldl Set.union Set.empty
                        |> Set.member ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "decimal" ] ], [ "decimal" ] )

                imports : List ImportDeclaration
                imports =
                    if shouldImportSDK then
                        [ LibraryImport morphirTypeSpecSDK ]

                    else
                        []
            in
            mapPackageDefinition packageDef distro
                |> Result.map (PrettyPrinter.prettyPrint packageName imports)
                |> Result.map (Dict.singleton ( [], Path.toString IRName.toTitleCase "." packageName ++ ".tsp" ))


mapPackageDefinition : Package.Definition () (IRType.Type ()) -> Distribution -> Result Errors (Dict Namespace NamespaceDeclaration)
mapPackageDefinition packageDef ir =
    packageDef.modules
        |> Dict.toList
        |> List.map
            (\( moduleName, accessControlledModDef ) ->
                accessControlledModDef.value
                    |> mapModuleDefinition ir
                    |> Result.map
                        (Tuple.pair (moduleName |> List.map IRName.toTitleCase))
            )
        |> ResultList.keepFirstError
        |> Result.map Dict.fromList


mapModuleDefinition : Distribution -> Module.Definition () (IRType.Type ()) -> Result Errors NamespaceDeclaration
mapModuleDefinition ir definition =
    definition.types
        |> Dict.toList
        |> List.map
            (\( tpeName, accessControlledDoc ) ->
                accessControlledDoc.value.value
                    |> mapTypeDefinition ir tpeName
            )
        |> ResultList.keepFirstError
        |> Result.map Dict.fromList


mapTypeDefinition : Distribution -> IRName.Name -> IRType.Definition () -> Result Errors ( AST.Name, TypeDefinition )
mapTypeDefinition ir tpeName definition =
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

                maybeScalarType : Maybe AST.Type
                maybeScalarType =
                    case accessControlled.value |> Dict.toList of
                        ( ctorName, ( argName, argType ) :: [] ) :: [] ->
                            if tpeName == ctorName then
                                case mapType argType of
                                    Ok (Scalar typ) ->
                                        Just (Scalar typ)

                                    Ok (AST.Reference _ _ _) ->
                                        scalarTypeFromType ir argType

                                    _ ->
                                        Nothing

                            else
                                Nothing

                        _ ->
                            Nothing
            in
            case maybeScalarType of
                Just scalarTypeExp ->
                    ScalarDefinition scalarTypeExp
                        |> Tuple.pair (iRNameToName tpeName)
                        |> Ok

                Nothing ->
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
                    Ok (AST.Scalar Boolean)

                ( "Morphir.SDK:Basics:int", [] ) ->
                    Ok (AST.Scalar Integer)

                ( "Morphir.SDK:Basics:float", [] ) ->
                    Ok (AST.Scalar Float)

                ( "Morphir.SDK:String:string", [] ) ->
                    Ok (AST.Scalar String)

                ( "Morphir.SDK:Char:char", [] ) ->
                    Ok (AST.Scalar String)

                ( "Morphir.SDK:LocalDate:localDate", [] ) ->
                    Ok (AST.Scalar PlainDate)

                ( "Morphir.SDK:LocalTime:localTime", [] ) ->
                    Ok (AST.Scalar PlainTime)

                ( "Morphir.SDK:Decimal:decimal", [] ) ->
                    Ok (AST.Reference [] [ "Morphir", "SDK", "Decimal" ] "Decimal")

                ( "Morphir.SDK:Month:month", [] ) ->
                    Ok (AST.Scalar String)

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
                                    , AST.Scalar Null
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


mapScalarType : FQName -> List (IRType.Type ()) -> Maybe AST.Type
mapScalarType fQName types =
    case ( FQName.toString fQName, types ) of
        ( "Morphir.SDK:Basics:bool", [] ) ->
            Just (AST.Scalar Boolean)

        ( "Morphir.SDK:Basics:int", [] ) ->
            Just (AST.Scalar Integer)

        ( "Morphir.SDK:Basics:float", [] ) ->
            Just (AST.Scalar Float)

        ( "Morphir.SDK:String:string", [] ) ->
            Just (AST.Scalar String)

        ( "Morphir.SDK:Char:char", [] ) ->
            Just (AST.Scalar String)

        ( "Morphir.SDK:LocalDate:localDate", [] ) ->
            Just (AST.Scalar PlainDate)

        ( "Morphir.SDK:LocalTime:localTime", [] ) ->
            Just (AST.Scalar PlainTime)

        ( "Morphir.SDK:Decimal:decimal", [] ) ->
            Just (AST.Reference [] [ "Morphir", "SDK", "Decimal" ] "Decimal")

        ( "Morphir.SDK:Month:month", [] ) ->
            Just (AST.Scalar String)

        _ ->
            Nothing


scalarTypeFromType : Distribution -> IRType.Type () -> Maybe AST.Type
scalarTypeFromType ir typ =
    case typ of
        IRType.Reference _ (( packageName, moduleName, localName ) as fQName) argTypes ->
            case argTypes |> mapScalarType fQName of
                Just (Scalar tpe) ->
                    Just (Scalar tpe)

                _ ->
                    case Distribution.lookupTypeSpecification fQName ir of
                        Just typSpec ->
                            case typSpec of
                                TypeAliasSpecification [] tpe ->
                                    case mapType tpe of
                                        Ok (Scalar typp) ->
                                            Just (Scalar typp)

                                        _ ->
                                            Nothing

                                CustomTypeSpecification [] ctors ->
                                    case ctors |> Dict.toList of
                                        ( ctorName, ( argName, argType ) :: [] ) :: [] ->
                                            scalarTypeFromType ir argType

                                        _ ->
                                            Nothing

                                _ ->
                                    Nothing

                        _ ->
                            Nothing

        _ ->
            Nothing
