module Morphir.Snowpark.Customization exposing
    ( CustomizationOptions
    , emptyCustomizationOptions
    , generateCacheCode
    , loadCustomizationOptions
    , tryToApplyPostConversionCustomization
    )

import Json.Decode as Decode
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.NodeId exposing (NodeID(..))
import Morphir.SDK.Dict as SDKDict
import Morphir.Scala.AST as Scala exposing (ImportName(..))
import Set exposing (Set)


type alias CustomizationOptions =
    { functionsToInline : Set FQName
    , functionsToCache : Set FQName
    }


emptyCustomizationOptions : CustomizationOptions
emptyCustomizationOptions =
    CustomizationOptions Set.empty Set.empty


loadCustomizationOptions : SDKDict.Dict NodeID Decode.Value -> CustomizationOptions
loadCustomizationOptions optionsDict =
    let
        decodeFirstElementAsString =
            Decode.decodeValue (Decode.index 0 Decode.string)

        optsList =
            optionsDict
                |> SDKDict.toList

        functions =
            optsList
                |> List.filterMap
                    (\( id, value ) ->
                        case id of
                            ValueID fullName _ ->
                                Just ( fullName, value )

                            _ ->
                                Nothing
                    )

        ( functionsToCache, valuesToInline ) =
            functions
                |> List.foldr
                    (\( fullName, valueDec ) (( toCache, toInline ) as current) ->
                        case decodeFirstElementAsString valueDec of
                            Ok "cacheResult" ->
                                ( Set.insert fullName toCache, toInline )

                            Ok "inlineElement" ->
                                ( toCache, Set.insert fullName toInline )

                            _ ->
                                current
                    )
                    ( Set.empty, Set.empty )
    in
    { functionsToInline = valuesToInline
    , functionsToCache = functionsToCache
    }


generateCacheCode : String -> Scala.MemberDecl -> Maybe Scala.Type -> Scala.MemberDecl
generateCacheCode cacheName decl returnType =
    case decl of
        Scala.FunctionDecl funcInfo ->
            let
                funcArgs =
                    funcInfo.args |> List.concatMap (\t -> t |> List.map (\t2 -> Scala.Variable t2.name))

                body =
                    Maybe.withDefault (Scala.Variable "_") funcInfo.body

                expressionToCache =
                    case returnType of
                        Just (Scala.TypeRef _ "DataFrame") ->
                            Scala.Select body "cacheResult"

                        _ ->
                            body

                getOrElseUpdateCall =
                    Scala.Apply (Scala.Ref [ cacheName ] "getOrElseUpdate")
                        [ Scala.ArgValue Nothing (Scala.Tuple funcArgs)
                        , Scala.ArgValue Nothing expressionToCache
                        ]
            in
            Scala.FunctionDecl { funcInfo | body = Just getOrElseUpdateCall }

        _ ->
            decl


tryToApplyPostConversionCustomization : FQName -> Scala.MemberDecl -> CustomizationOptions -> Maybe ( List Scala.MemberDecl, List Scala.ImportDecl )
tryToApplyPostConversionCustomization fullFunctionName mappedFunction customizationOptions =
    case ( Set.member fullFunctionName customizationOptions.functionsToCache, mappedFunction ) of
        ( True, Scala.FunctionDecl funcInfo ) ->
            Just
                ( [ generateCacheCode (funcInfo.name ++ "Cache") mappedFunction funcInfo.returnType
                  , Scala.ValueDecl
                        { modifiers = []
                        , pattern = Scala.NamedMatch (funcInfo.name ++ "Cache")
                        , valueType =
                            Just
                                (Scala.TypeApply
                                    (Scala.TypeRef [ "scala", "collection", "concurrent" ] "Map")
                                    [ Scala.TupleType (funcInfo.args |> List.concatMap (\t -> t |> List.map (\t2 -> t2.tpe))), Maybe.withDefault (Scala.TypeVar "_") funcInfo.returnType ]
                                )
                        , value =
                            Scala.Select (Scala.New [ "java", "util", "concurrent" ] "ConcurrentHashMap" []) "asScala"
                        }
                  ]
                , [ Scala.ImportDecl False [ "scala", "collection", "JavaConverters", "_" ] [] ]
                )

        _ ->
            if Set.member fullFunctionName customizationOptions.functionsToInline then
                Just ( [], [] )

            else
                Nothing
