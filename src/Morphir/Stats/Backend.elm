module Morphir.Stats.Backend exposing (..)

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (Distribution(..))
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Literal as Literal
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package
import Morphir.IR.Path as Path
import Morphir.IR.Type as Type
import Morphir.IR.Value as Value


type alias FeatureCollection =
    List FeatureFrequency


type alias FeatureFrequency =
    ( Feature, Frequency )


type alias Feature =
    String


type alias Frequency =
    Int


collectFeaturesFromDistribution : Distribution -> FileMap
collectFeaturesFromDistribution distribution =
    case distribution of
        Library _ _ packageDefinition ->
            let
                featureList =
                    collectFeaturesFromPackage distribution packageDefinition

                encodedFeatureListAsJSON : String
                encodedFeatureListAsJSON =
                    featureList
                        |> Dict.fromList
                        |> Encode.dict identity Encode.int
                        |> Encode.encode 4

                featureListFormattedAsMD : String
                featureListFormattedAsMD =
                    featureList
                        |> List.sortBy Tuple.second
                        |> List.reverse
                        |> List.map (\( feat, freq ) -> "- [ ] " ++ feat ++ " - " ++ String.fromInt freq)
                        |> List.append [ "# Morphir Features & Frequencies\n" ]
                        |> String.join "\n"
            in
            [ ( ( [], "FeatureMetrics.json" ), encodedFeatureListAsJSON )
            , ( ( [], "FeatureMetrics.md" ), featureListFormattedAsMD )
            ]
                |> Dict.fromList


collectFeaturesFromPackage : Distribution -> Package.Definition ta va -> FeatureCollection
collectFeaturesFromPackage ir definition =
    let
        emptyFeatureCollection =
            []

        types : List (AccessControlled (Documented (Type.Definition ta)))
        types =
            Dict.values definition.modules
                |> List.map (.value >> .types >> Dict.values)
                |> List.concat

        values : List (Value.Definition ta va)
        values =
            Dict.values definition.modules
                |> List.map (.value >> .values >> Dict.values >> List.map (.value >> .value))
                |> List.concat
    in
    emptyFeatureCollection
        |> collectTypeFeatures ir types
        |> collectFeaturesFromValueDefs ir values


collectTypeFeatures : Distribution -> List (AccessControlled (Documented (Type.Definition ta))) -> FeatureCollection -> FeatureCollection
collectTypeFeatures ir types featureCollection =
    let
        typeFeaturesFromTypes : FeatureCollection
        typeFeaturesFromTypes =
            types
                |> List.foldl
                    (\accDocTypeDef featureSetSoFar ->
                        case accDocTypeDef.value.value of
                            Type.TypeAliasDefinition names tpe ->
                                let
                                    withTypeAlias =
                                        incrementOrAdd "Type.TypeAlias" featureSetSoFar

                                    withTypeVariables =
                                        if List.length names > 0 then
                                            incrementOrAdd "Type.Variable" featureSetSoFar

                                        else
                                            withTypeAlias
                                in
                                collectFeaturesFromType ir tpe withTypeVariables

                            Type.CustomTypeDefinition names accessControlledConstructors ->
                                let
                                    withCustomType =
                                        incrementOrAdd "Type.CustomType" featureSetSoFar

                                    withCustomTypeVariables =
                                        if List.length names > 0 then
                                            incrementOrAdd "Type.Variable" featureSetSoFar

                                        else
                                            withCustomType
                                in
                                accessControlledConstructors.value
                                    |> Dict.values
                                    |> List.concat
                                    |> List.map Tuple.second
                                    |> List.foldl (collectFeaturesFromType ir) withCustomTypeVariables
                    )
                    featureCollection
    in
    typeFeaturesFromTypes


collectFeaturesFromType : Distribution -> Type.Type ta -> FeatureCollection -> FeatureCollection
collectFeaturesFromType ir tpe featureCollection =
    case tpe of
        Type.Variable _ _ ->
            incrementOrAdd "Type.Variable" featureCollection

        -- TODO collect references to sdk types
        Type.Reference _ fQName types ->
            let
                extractTypes fqn =
                    case Distribution.lookupTypeSpecification fqn ir of
                        Just spec ->
                            case spec of
                                Type.TypeAliasSpecification _ t ->
                                    Type.mapTypeAttributes (always (Type.typeAttributes tpe)) t :: types

                                Type.OpaqueTypeSpecification _ ->
                                    types

                                Type.CustomTypeSpecification _ constructors ->
                                    Dict.values constructors
                                        |> List.concat
                                        |> List.map (Tuple.second >> Type.mapTypeAttributes (always (Type.typeAttributes tpe)))
                                        |> List.append types

                                Type.DerivedTypeSpecification _ config ->
                                    Type.mapTypeAttributes (always (Type.typeAttributes tpe)) config.baseType :: types

                        Nothing ->
                            types
            in
            extractTypes fQName
                |> List.foldl (collectFeaturesFromType ir)
                    (incrementOrAdd "Type.Reference" featureCollection)
                |> collectSDKFeatures fQName

        Type.Tuple _ types ->
            types
                |> List.foldl (collectFeaturesFromType ir)
                    (incrementOrAdd "Type.Tuple" featureCollection)

        Type.Record _ fields ->
            fields
                |> List.map .tpe
                |> List.foldl (collectFeaturesFromType ir)
                    (incrementOrAdd "Type.Record" featureCollection)

        Type.ExtensibleRecord _ _ fields ->
            fields
                |> List.map .tpe
                |> List.foldl (collectFeaturesFromType ir)
                    (incrementOrAdd "Type.ExtensibleRecord" featureCollection)

        Type.Function _ inputType outputType ->
            [ inputType, outputType ]
                |> List.foldl (collectFeaturesFromType ir)
                    (incrementOrAdd "Type.Function" featureCollection)

        Type.Unit _ ->
            incrementOrAdd "Type.Unit" featureCollection


collectFeaturesFromValueDefs : Distribution -> List (Value.Definition ta va) -> FeatureCollection -> FeatureCollection
collectFeaturesFromValueDefs ir values featureCollection =
    let
        collectTypesFromValueDef : Value.Definition ta va -> List (Type.Type ta)
        collectTypesFromValueDef def =
            List.map (\( _, _, tpe ) -> tpe) def.inputTypes
                |> List.append [ def.outputType ]

        typeAndValueFeaturesFromValueSign : FeatureCollection
        typeAndValueFeaturesFromValueSign =
            values
                |> List.foldl
                    (\valueDef featureSetSoFar ->
                        collectTypesFromValueDef valueDef
                            |> List.foldl (collectFeaturesFromType ir) featureSetSoFar
                            |> collectFeaturesFromValue ir valueDef.body
                    )
                    featureCollection
    in
    typeAndValueFeaturesFromValueSign


collectFeaturesFromValue : Distribution -> Value.Value ta va -> FeatureCollection -> FeatureCollection
collectFeaturesFromValue ir value featureCollection =
    case value of
        Value.Literal _ literal ->
            incrementOrAdd "Value.Literal" featureCollection
                |> collectLiteralFeatures literal

        Value.Constructor _ _ ->
            incrementOrAdd "Value.Constructor" featureCollection

        Value.Tuple _ values ->
            values
                |> List.foldl (collectFeaturesFromValue ir)
                    (incrementOrAdd "Value.Tuple" featureCollection)

        Value.List _ values ->
            values
                |> List.foldl (collectFeaturesFromValue ir)
                    (incrementOrAdd "Value.List" featureCollection)

        Value.Record _ values ->
            values
                |> Dict.values
                |> List.foldl (collectFeaturesFromValue ir)
                    (incrementOrAdd "Value.Record" featureCollection)

        Value.Variable _ _ ->
            incrementOrAdd "Value.Variable" featureCollection

        Value.Reference _ fqn ->
            incrementOrAdd "Value.Reference" featureCollection
                |> collectSDKFeatures fqn

        Value.Field _ _ _ ->
            incrementOrAdd "Value.Field" featureCollection

        Value.FieldFunction _ _ ->
            incrementOrAdd "Value.FieldFunction" featureCollection

        (Value.Apply _ _ _) as apply ->
            let
                argsAndTarget lst v =
                    case v of
                        Value.Apply _ target args ->
                            argsAndTarget (args :: lst) target

                        _ ->
                            ( lst, v )
            in
            argsAndTarget [] apply
                |> (\( args, targetVal ) ->
                        List.foldl (collectFeaturesFromValue ir)
                            (incrementOrAdd "Value.Apply" featureCollection)
                            args
                            |> collectFeaturesFromValue ir targetVal
                   )

        Value.Lambda _ pattern _ ->
            incrementOrAdd "Value.Lambda" featureCollection
                |> collectPatternFeatures pattern

        Value.LetDefinition _ _ _ _ ->
            incrementOrAdd "Value.LetDefinition" featureCollection

        Value.LetRecursion _ definitions inValue ->
            incrementOrAdd "Value.LetRecursion" featureCollection
                |> collectFeaturesFromValueDefs ir (Dict.values definitions)
                |> collectFeaturesFromValue ir inValue

        Value.Destructure _ pattern fromValue toValue ->
            [ fromValue, toValue ]
                |> List.foldl (collectFeaturesFromValue ir)
                    (incrementOrAdd "Value.Destructure" featureCollection)
                |> collectPatternFeatures pattern

        Value.IfThenElse _ cond thenBlock elseBlock ->
            [ cond, thenBlock, elseBlock ]
                |> List.foldl (collectFeaturesFromValue ir)
                    (incrementOrAdd "Value.IfThenElse" featureCollection)

        Value.PatternMatch _ _ patterns ->
            patterns
                |> List.map Tuple.first
                |> List.foldl collectPatternFeatures
                    (incrementOrAdd "Value.PatternMatch" featureCollection)

        Value.UpdateRecord _ _ updates ->
            updates
                |> Dict.values
                |> List.foldl (collectFeaturesFromValue ir)
                    (incrementOrAdd "Value.UpdateRecord" featureCollection)

        Value.Unit _ ->
            incrementOrAdd "Value.Unit" featureCollection


collectLiteralFeatures : Literal.Literal -> FeatureCollection -> FeatureCollection
collectLiteralFeatures literal featureCollection =
    case literal of
        Literal.BoolLiteral _ ->
            incrementOrAdd "BoolLiteral" featureCollection

        Literal.CharLiteral _ ->
            incrementOrAdd "CharLiteral" featureCollection

        Literal.StringLiteral _ ->
            incrementOrAdd "StringLiteral" featureCollection

        Literal.WholeNumberLiteral _ ->
            incrementOrAdd "WholeNumberLiteral" featureCollection

        Literal.FloatLiteral _ ->
            incrementOrAdd "FloatLiteral" featureCollection

        Literal.DecimalLiteral _ ->
            Debug.todo "branch 'DecimalLiteral _' not implemented"


collectPatternFeatures : Value.Pattern a -> FeatureCollection -> FeatureCollection
collectPatternFeatures pattern featureCollection =
    case pattern of
        Value.AsPattern _ (Value.WildcardPattern _) _ ->
            featureCollection

        Value.WildcardPattern _ ->
            incrementOrAdd "WildcardPattern" featureCollection

        Value.AsPattern _ pat _ ->
            incrementOrAdd "AsPattern" featureCollection
                |> collectPatternFeatures pat

        Value.TuplePattern _ patterns ->
            patterns
                |> List.foldl collectPatternFeatures
                    (incrementOrAdd "TuplePattern" featureCollection)

        Value.ConstructorPattern _ _ patterns ->
            patterns
                |> List.foldl collectPatternFeatures
                    (incrementOrAdd "ConstructorPattern" featureCollection)

        Value.EmptyListPattern _ ->
            incrementOrAdd "EmptyListPattern" featureCollection

        Value.HeadTailPattern _ head tail ->
            [ head, tail ]
                |> List.foldl collectPatternFeatures
                    (incrementOrAdd "HeadTailPattern" featureCollection)

        Value.LiteralPattern _ literal ->
            incrementOrAdd "LiteralPattern" featureCollection
                |> collectLiteralFeatures literal

        Value.UnitPattern _ ->
            incrementOrAdd "UnitPattern" featureCollection


collectSDKFeatures : FQName -> FeatureCollection -> FeatureCollection
collectSDKFeatures (( packagePath, _, _ ) as fqn) featureCollection =
    case Path.toString Name.toTitleCase "." packagePath of
        "Morphir.SDK" ->
            incrementOrAdd
                (FQName.toString fqn)
                featureCollection

        _ ->
            featureCollection


incrementOrAdd : Feature -> FeatureCollection -> FeatureCollection
incrementOrAdd feature features =
    let
        featureInFeatures =
            features
                |> List.filter
                    (\( feat, _ ) -> feat == feature)

        featuresWithoutFeature =
            features
                |> List.filter
                    (\( feat, _ ) -> feat /= feature)
    in
    case featureInFeatures of
        -- add if it's not in the list
        [] ->
            featuresWithoutFeature
                |> List.append [ ( feature, 1 ) ]

        [ ( feat, freq ) ] ->
            featuresWithoutFeature
                |> List.append [ ( feat, freq + 1 ) ]

        more ->
            let
                cumulativeFreq =
                    more |> List.foldl (\( _, freq ) total -> total + freq) 0
            in
            featuresWithoutFeature
                |> List.append [ ( feature, cumulativeFreq + 1 ) ]
