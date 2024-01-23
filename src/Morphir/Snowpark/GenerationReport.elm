module Morphir.Snowpark.GenerationReport exposing
    ( GenerationIssue
    , GenerationIssues
    , addGenerationIssue
    , createGenerationReport
    )

import Dict exposing (Dict)
import Morphir.File.SourceCode exposing (Doc)
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.Snowpark.Customization exposing (CustomizationOptions)
import Morphir.Snowpark.MappingContext
    exposing
        ( FunctionClassification(..)
        , GlobalDefinitionInformation
        , isRecordWithSimpleTypes
        )


type alias GenerationIssue =
    String


type alias GenerationIssues =
    Dict FQName (List GenerationIssue)


addGenerationIssue : FQName -> GenerationIssue -> GenerationIssues -> GenerationIssues
addGenerationIssue fullElementName issueInfo generationIssues =
    Dict.update fullElementName
        (\oldValueMaybe -> Just <| issueInfo :: Maybe.withDefault [] oldValueMaybe)
        generationIssues


type MdElem
    = Header1 String
    | Header2 String
    | Header3 String
    | Paragraph (List MdInline)
    | BulletList (List (List MdInline))


type MdInline
    = Span String
    | Strong String
    | Code String


type alias MdDoc =
    List MdElem


toStringMd : MdDoc -> List String
toStringMd doc =
    doc
        |> List.map toStringMdElem
        |> List.intersperse [ "\n" ]
        |> List.concat


toStringMdElem : MdElem -> List String
toStringMdElem e =
    case e of
        Header1 txt ->
            [ "# ", txt, "\n" ]

        Header2 txt ->
            [ "\n", "## ", txt, "\n" ]

        Header3 txt ->
            [ "\n", "### ", txt, "\n" ]

        Paragraph items ->
            items |> List.map toStringMdInline

        BulletList items ->
            items
                |> List.map (\innerList -> "- " :: List.map toStringMdInline innerList)
                |> List.intersperse [ "\n" ]
                |> List.concat


toStringMdInline : MdInline -> String
toStringMdInline inlineElement =
    case inlineElement of
        Span str ->
            str

        Strong str ->
            "**" ++ str ++ "**"

        Code str ->
            "`" ++ str ++ "`"


generateSortedListOfCodeFromNames : List FQName -> List (List MdInline)
generateSortedListOfCodeFromNames names =
    names
        |> List.map FQName.toString
        |> List.sort
        |> List.map (\fname -> [ Code fname ])


generateDataFrameListing : GlobalDefinitionInformation () -> List MdElem
generateDataFrameListing ( typeInformation, _, _ ) =
    let
        bullets =
            typeInformation
                |> Dict.toList
                |> List.filter (\( fname, _ ) -> isRecordWithSimpleTypes fname typeInformation)
                |> List.map Tuple.first
                |> generateSortedListOfCodeFromNames
    in
    [ Header2 "Types identified as DataFrames"
    , BulletList bullets
    ]


generateIssuesReport : GenerationIssues -> List MdElem
generateIssuesReport issues =
    if Dict.isEmpty issues then
        []

    else
        Header2 "Generation issues"
            :: (issues
                    |> Dict.toList
                    |> List.concatMap
                        (\( func, innerIssues ) -> [ Header3 (FQName.toString func), BulletList (innerIssues |> List.map (\i -> [ Span i ])) ])
               )


generateFunctionClassificationListing : GlobalDefinitionInformation () -> List MdElem
generateFunctionClassificationListing ( _, functionClassification, _ ) =
    functionClassification
        |> Dict.toList
        |> List.partition
            (\( _, cls ) ->
                case cls of
                    FromComplexValuesToDataFrames ->
                        True

                    FromComplexToValues ->
                        True

                    _ ->
                        False
            )
        |> (\( complex, df ) ->
                [ Header2 "Functions generated using DataFrame operations strategy"
                , BulletList (df |> List.map Tuple.first |> generateSortedListOfCodeFromNames)
                , Header2 "Functions generated using Scala strategy"
                , BulletList (complex |> List.map Tuple.first |> generateSortedListOfCodeFromNames)
                ]
           )


createGenerationReport : GlobalDefinitionInformation () -> CustomizationOptions -> GenerationIssues -> Doc
createGenerationReport ctx _ issues =
    let
        mddoc =
            Header1 "Generation report"
                :: generateIssuesReport issues
                ++ generateFunctionClassificationListing ctx
                ++ generateDataFrameListing ctx
    in
    String.join "" (toStringMd mddoc)
