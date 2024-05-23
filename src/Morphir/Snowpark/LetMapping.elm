module Morphir.Snowpark.LetMapping exposing (collectNestedLetDeclarations, mapLetDefinition)

import List
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern(..), TypedValue, Value(..))
import Morphir.Scala.AST as Scala
import Morphir.Snowpark.Constants exposing (MapValueType, ValueGenerationResult)
import Morphir.Snowpark.GenerationReport exposing (GenerationIssue)
import Morphir.Snowpark.MappingContext
    exposing
        ( FunctionClassification(..)
        , ValueMappingContext
        , addLocalDefinitions
        )
import Morphir.Snowpark.TypeRefMapping exposing (mapTypeReference)


mapLetDefinition : Name.Name -> Value.Definition () (Type ()) -> TypedValue -> MapValueType -> ValueMappingContext -> ValueGenerationResult
mapLetDefinition name definition body mapValue ctx =
    let
        ( pairs, bodyToConvert ) =
            collectNestedLetDeclarations body []

        declsToProcess =
            ( name, definition ) :: pairs

        contextForLetBody =
            addLocalDefinitions (declsToProcess |> List.map Tuple.first) ctx

        ( decls, issues ) =
            declsToProcess
                |> List.map (\p -> mapLetDeclaration p mapValue contextForLetBody)
                |> List.unzip

        ( mappedBody, mappedBodyIssues ) =
            mapValue bodyToConvert contextForLetBody
    in
    ( Scala.Block decls mappedBody, mappedBodyIssues ++ List.concat issues )


mapLetDeclaration : ( Name.Name, Value.Definition () (Type ()) ) -> MapValueType -> ValueMappingContext -> ( Scala.MemberDecl, List GenerationIssue )
mapLetDeclaration ( name, decl ) mapValue ctx =
    case decl.body of
        Value.Lambda _ (Value.AsPattern t _ paramName) body ->
            let
                ( mappedBody, mappedBodyIssues ) =
                    mapValue body ctx

                mappedArgType =
                    mapTypeReference t ctx.currentFunctionClassification ctx.typesContextInfo
            in
            ( Scala.FunctionDecl
                { modifiers = []
                , name = Name.toCamelCase name
                , typeArgs = []
                , args = [ [ Scala.ArgDecl [] mappedArgType (Name.toCamelCase paramName) Nothing ] ]
                , returnType = Nothing
                , body = Just mappedBody
                }
            , mappedBodyIssues
            )

        _ ->
            let
                ( mappedBody, mappedBodyIssues ) =
                    mapValue decl.body ctx
            in
            ( Scala.ValueDecl
                { modifiers = []
                , pattern = Scala.NamedMatch (name |> Name.toCamelCase)
                , valueType = Nothing
                , value = mappedBody
                }
            , mappedBodyIssues
            )


collectNestedLetDeclarations :
    TypedValue
    -> List ( Name.Name, Value.Definition () (Type ()) )
    -> ( List ( Name.Name, Value.Definition () (Type ()) ), TypedValue )
collectNestedLetDeclarations currentBody collectedPairs =
    case currentBody of
        Value.LetDefinition _ name definition body ->
            collectNestedLetDeclarations body (( name, definition ) :: collectedPairs)

        _ ->
            ( List.reverse collectedPairs, currentBody )
