module Morphir.Snowpark.LetMapping exposing (mapLetDefinition)

import List
import Morphir.IR.Name as Name
import Morphir.Scala.AST as Scala
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.IR.Type exposing (Type)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.Snowpark.TypeRefMapping exposing (mapTypeReference)
import Morphir.Snowpark.MappingContext exposing ( ValueMappingContext )
import Morphir.Snowpark.MappingContext exposing (FunctionClassification(..))
import Morphir.Snowpark.MappingContext exposing (addLocalDefinitions)
import Morphir.Snowpark.Constants exposing (MapValueType)

mapLetDefinition : Name.Name -> Value.Definition ta (Type ()) -> Value ta (Type ()) -> MapValueType ta -> ValueMappingContext-> Scala.Value
mapLetDefinition name definition body mapValue ctx =
        let 
            (pairs, bodyToConvert) = collectNestedLetDeclarations body []
            declsToProcess = ((name, definition) :: pairs)
            contextForLetBody = addLocalDefinitions (declsToProcess |> List.map Tuple.first) ctx
            decls = declsToProcess
                        |> List.map (\p -> mapLetDeclaration p mapValue contextForLetBody)
        in
        Scala.Block decls (mapValue bodyToConvert contextForLetBody)

mapLetDeclaration : (Name.Name, Value.Definition ta (Type ())) -> MapValueType ta -> ValueMappingContext -> Scala.MemberDecl
mapLetDeclaration (name, decl) mapValue ctx =
    case decl.body of
        Value.Lambda _ (Value.AsPattern t _ paramName) body ->
            Scala.FunctionDecl { modifiers = []
                               , name = Name.toCamelCase name
                               , typeArgs = []
                               , args = [ [ Scala.ArgDecl [] (mapTypeReference t ctx.currentFunctionClassification ctx.typesContextInfo) (Name.toCamelCase paramName) Nothing] ]
                               , returnType = Nothing
                               , body = Just (mapValue body ctx)
                               }
        _ ->
            Scala.ValueDecl { modifiers = []
                            , pattern = Scala.NamedMatch (name |> Name.toCamelCase)
                            , valueType = Nothing
                            , value = mapValue decl.body ctx
                            }


collectNestedLetDeclarations : Value ta (Type ()) -> 
                                  List (Name.Name, Value.Definition ta (Type ())) ->
                                  (List (Name.Name, Value.Definition ta (Type ())), Value ta (Type ())) 
collectNestedLetDeclarations currentBody collectedPairs =
    case currentBody of
        Value.LetDefinition _ name definition body ->
            collectNestedLetDeclarations body ((name, definition)::collectedPairs)
        _ -> 
            (List.reverse collectedPairs, currentBody)