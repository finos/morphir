module Morphir.Visual.XRayView exposing (NodeType(..), TreeNode(..), childNodes, noPadding, patternToNode, valueToNode, viewConstructorName, viewLiteral, viewPatternAsHeader, viewReferenceName, viewTreeNode, viewType, viewValue, viewValueAsHeader, viewValueDefinition)

import Dict
import Element exposing (Element, column, el, fill, link, paddingEach, paddingXY, rgb, row, spacing, text, width, pointer)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type)
import Morphir.IR.Value as Value exposing (Pattern, Value)
import Morphir.SDK.Decimal as Decimal
import Morphir.Visual.Common exposing (grayScale)


viewValueDefinition : (va -> Element msg) -> Value.Definition ta va -> Element msg
viewValueDefinition viewValueAttr valueDef =
    viewValue viewValueAttr valueDef.body


viewValue : (va -> Element msg) -> Value ta va -> Element msg
viewValue viewValueAttr value =
    el
        [ Font.family [ Font.monospace ]
        , Font.color (grayScale 0.3)
        ]
        (value
            |> valueToNode Nothing
            |> viewTreeNode viewValueAttr
        )


type TreeNode ta va
    = TreeNode (Maybe String) (NodeType ta va) (List (TreeNode ta va))


type NodeType ta va
    = ValueNode (Value ta va)
    | PatternNode (Pattern va)


childNodes : TreeNode ta va -> List (TreeNode ta va)
childNodes treeNode =
    case treeNode of
        TreeNode _ _ treeNodes ->
            treeNodes


viewTreeNode : (va -> Element msg) -> TreeNode ta va -> Element msg
viewTreeNode viewValueAttr (TreeNode maybeTag nodeType treeNodes) =
    let
        viewHeaderAndChildren : Element msg -> Element msg -> List (Element msg) -> Element msg
        viewHeaderAndChildren header attr children =
            column
                [ width fill, spacing 5 ]
                [ row [ width fill, spacing 5 ]
                    [ case maybeTag of
                        Just tag ->
                            row [ spacing 5 ]
                                [ el
                                    [ Font.color (grayScale 0.7)
                                    ]
                                    (text tag)
                                , header
                                ]

                        Nothing ->
                            header
                    , el
                        [ paddingXY 10 2
                        , Background.color (rgb 1 0.9 0.8)
                        , Border.rounded 3
                        ]
                        attr
                    ]
                , column
                    [ width fill
                    , paddingEach { noPadding | left = 20 }
                    ]
                    children
                ]
    in
    case nodeType of
        ValueNode value ->
            viewHeaderAndChildren
                (viewValueAsHeader value)
                (value |> Value.valueAttribute |> viewValueAttr)
                (List.map (viewTreeNode viewValueAttr) treeNodes)

        PatternNode pattern ->
            viewHeaderAndChildren
                (viewPatternAsHeader pattern)
                (pattern |> Value.patternAttribute |> viewValueAttr)
                (List.map (viewTreeNode viewValueAttr) treeNodes)


viewValueAsHeader : Value ta va -> Element msg
viewValueAsHeader value =
    let
        dataLabel : String -> Element msg
        dataLabel labelText =
            el
                [ paddingXY 6 3
                , Border.rounded 3
                , Background.color (rgb 0.9 0.9 1)
                ]
                (text labelText)

        logicLabel : String -> Element msg
        logicLabel labelText =
            el
                [ paddingXY 6 3
                , Border.rounded 3
                , Background.color (rgb 0.9 1 0.9)
                ]
                (text labelText)

        header : List (Element msg) -> Element msg
        header elems =
            row [ spacing 5 ] elems
    in
    case value of
        Value.Literal _ lit ->
            header
                [ dataLabel "Literal"
                , viewLiteral lit
                ]

        Value.Constructor _ fQName ->
            header
                [ dataLabel "Constructor"
                , viewConstructorName fQName
                ]

        Value.Tuple _ items ->
            if List.isEmpty items then
                header [ dataLabel "Tuple", text "()" ]

            else
                header [ dataLabel "Tuple" ]

        Value.List _ items ->
            if List.isEmpty items then
                header [ dataLabel "List", text "[]" ]

            else
                header [ dataLabel "List" ]

        Value.Record _ fields ->
            if Dict.isEmpty fields then
                header [ dataLabel "Record", text "{}" ]

            else
                header [ dataLabel "Record" ]

        Value.Variable _ varName ->
            header [ logicLabel "Variable", text (varName |> Name.toCamelCase) ]

        Value.Reference _ fQName ->
            header
                [ logicLabel "Reference"
                , viewReferenceName fQName
                ]

        Value.Field _ _ fieldName ->
            header [ logicLabel "Field", text (fieldName |> Name.toCamelCase) ]

        Value.FieldFunction _ fieldName ->
            header [ logicLabel "FieldFunction", text (fieldName |> Name.toCamelCase) ]

        Value.Apply _ _ _ ->
            header [ logicLabel "Apply" ]

        Value.Lambda _ _ _ ->
            header [ logicLabel "Lambda" ]

        Value.LetDefinition _ _ _ _ ->
            header [ logicLabel "LetDefinition" ]

        Value.LetRecursion _ _ _ ->
            header [ logicLabel "LetRecursion" ]

        Value.Destructure _ _ _ _ ->
            header [ logicLabel "Destructure" ]

        Value.IfThenElse _ _ _ _ ->
            header [ logicLabel "IfThenElse" ]

        Value.PatternMatch _ _ _ ->
            header [ logicLabel "PatternMatch" ]

        Value.UpdateRecord _ _ _ ->
            header [ logicLabel "UpdateRecord" ]

        Value.Unit _ ->
            header [ logicLabel "Unit" ]


viewPatternAsHeader : Pattern va -> Element msg
viewPatternAsHeader pattern =
    let
        nodeLabel : String -> Element msg
        nodeLabel labelText =
            el
                [ paddingXY 6 3
                , Border.rounded 3
                , Background.color (rgb 1 0.9 1)
                ]
                (text labelText)

        header : List (Element msg) -> Element msg
        header elems =
            row [ spacing 5 ] elems
    in
    case pattern of
        Value.WildcardPattern _ ->
            header [ nodeLabel "WildcardPattern" ]

        Value.AsPattern _ _ name ->
            header [ nodeLabel "AsPattern", text (name |> Name.toCamelCase) ]

        Value.TuplePattern _ _ ->
            header [ nodeLabel "TuplePattern" ]

        Value.ConstructorPattern _ fQName _ ->
            header
                [ nodeLabel "ConstructorPattern"
                , viewConstructorName fQName
                ]

        Value.EmptyListPattern _ ->
            header [ nodeLabel "EmptyListPattern" ]

        Value.HeadTailPattern _ _ _ ->
            header [ nodeLabel "HeadTailPattern" ]

        Value.LiteralPattern _ literal ->
            header [ nodeLabel "LiteralPattern", viewLiteral literal ]

        Value.UnitPattern _ ->
            header [ nodeLabel "UnitPattern" ]


valueToNode : Maybe String -> Value ta va -> TreeNode ta va
valueToNode tag value =
    case value of
        Value.Tuple _ elems ->
            TreeNode tag
                (ValueNode value)
                (elems |> List.map (valueToNode Nothing))

        Value.List _ items ->
            TreeNode tag
                (ValueNode value)
                (items |> List.map (valueToNode Nothing))

        Value.Record _ fields ->
            TreeNode tag
                (ValueNode value)
                (fields
                    |> Dict.map
                        (\fieldName fieldValue ->
                            valueToNode (Just (fieldName |> Name.toCamelCase)) fieldValue
                        )
                    |> Dict.values
                )

        Value.Field _ subject _ ->
            TreeNode tag
                (ValueNode value)
                [ valueToNode (Just "subject") subject ]

        Value.Apply _ fun arg ->
            TreeNode tag
                (ValueNode value)
                [ valueToNode (Just "fun") fun
                , valueToNode (Just "arg") arg
                ]

        Value.Lambda _ arg body ->
            TreeNode tag
                (ValueNode value)
                [ patternToNode
                    (Just "\\")
                    arg
                , valueToNode (Just "->") body
                ]

        Value.LetDefinition _ _ _ _ ->
            let
                flattenLet : Value ta va -> ( Value ta va, List ( Name, Value.Definition ta va ) )
                flattenLet v =
                    case v of
                        Value.LetDefinition _ defName def inValue ->
                            let
                                ( subInValue, subDefs ) =
                                    flattenLet inValue
                            in
                            ( subInValue, ( defName, def ) :: subDefs )

                        _ ->
                            ( v, [] )

                ( bottomInValue, defs ) =
                    flattenLet value
            in
            TreeNode tag
                (ValueNode value)
                (List.concat
                    [ defs
                        |> List.map
                            (\( defName, def ) ->
                                valueToNode (Just (defName |> Name.toCamelCase)) def.body
                            )
                    , [ valueToNode (Just "in") bottomInValue ]
                    ]
                )

        Value.LetRecursion _ defs inValue ->
            TreeNode tag
                (ValueNode value)
                (List.concat
                    [ defs
                        |> Dict.toList
                        |> List.map
                            (\( defName, def ) ->
                                valueToNode (Just (defName |> Name.toCamelCase)) def.body
                            )
                    , [ valueToNode (Just "in") inValue ]
                    ]
                )

        Value.Destructure _ pattern subject inValue ->
            TreeNode tag
                (ValueNode value)
                [ patternToNode
                    Nothing
                    pattern
                , valueToNode (Just "=") subject
                , valueToNode (Just "in") inValue
                ]

        Value.IfThenElse _ cond thenBranch elseBranch ->
            TreeNode tag
                (ValueNode value)
                [ valueToNode (Just "cond") cond
                , valueToNode (Just "then") thenBranch
                , valueToNode (Just "else") elseBranch
                ]

        Value.PatternMatch _ subject cases ->
            TreeNode tag
                (ValueNode value)
                (List.concat
                    [ [ valueToNode (Just "case") subject ]
                    , cases
                        |> List.indexedMap
                            (\index ( casePattern, caseValue ) ->
                                [ patternToNode
                                    Nothing
                                    casePattern
                                , valueToNode
                                    (Just "->")
                                    caseValue
                                ]
                            )
                        |> List.concat
                    ]
                )

        Value.UpdateRecord _ subject fields ->
            TreeNode tag
                (ValueNode value)
                (List.concat
                    [ [ valueToNode Nothing subject ]
                    , fields
                        |> Dict.toList
                        |> List.map
                            (\( fieldName, fieldValue ) ->
                                valueToNode (Just (fieldName |> Name.toCamelCase)) fieldValue
                            )
                    ]
                )

        _ ->
            TreeNode tag (ValueNode value) []


patternToNode : Maybe String -> Pattern va -> TreeNode ta va
patternToNode maybeTag pattern =
    case pattern of
        Value.AsPattern _ target _ ->
            TreeNode maybeTag
                (PatternNode pattern)
                [ patternToNode Nothing target
                ]

        Value.TuplePattern _ elems ->
            TreeNode maybeTag
                (PatternNode pattern)
                (elems
                    |> List.map (patternToNode Nothing)
                )

        Value.ConstructorPattern _ _ args ->
            TreeNode maybeTag
                (PatternNode pattern)
                (args |> List.map (patternToNode Nothing))

        Value.HeadTailPattern _ head tail ->
            TreeNode maybeTag
                (PatternNode pattern)
                [ patternToNode Nothing head
                , patternToNode Nothing tail
                ]

        _ ->
            TreeNode maybeTag
                (PatternNode pattern)
                []


viewReferenceName : ( a, b, Name ) -> Element msg
viewReferenceName ( _, _, localName ) =
    text
        (localName |> Name.toCamelCase)


viewConstructorName : ( a, b, Name ) -> Element msg
viewConstructorName ( _, _, localName ) =
    text
        (localName |> Name.toTitleCase)


viewLiteral : Literal -> Element msg
viewLiteral lit =
    case lit of
        BoolLiteral bool ->
            if bool then
                text "True"

            else
                text "False"

        CharLiteral char ->
            text (String.concat [ "'", String.fromChar char, "'" ])

        StringLiteral string ->
            text (String.concat [ "\"", string, "\"" ])

        WholeNumberLiteral int ->
            text (String.fromInt int)

        FloatLiteral float ->
            text (String.fromFloat float)

        DecimalLiteral decimal ->
            text (Decimal.toString decimal)


noPadding : { left : number, right : number, top : number, bottom : number }
noPadding =
    { left = 0, right = 0, top = 0, bottom = 0 }


viewType : (Path -> String) -> Type () -> Element msg
viewType urlBuilder tpe =
    case tpe of
        Type.Variable _ varName ->
            text (Name.toCamelCase varName)

        Type.Reference _ ( b, c, localName ) argTypes ->
            if List.isEmpty argTypes then
                link [pointer] { url = "/home" ++ urlBuilder b ++ urlBuilder c ++ "/" ++ Name.toTitleCase localName, label = text <| Name.toTitleCase localName }

            else
                row [ spacing 6 ]
                    (List.concat
                        [ [ text (localName |> Name.toTitleCase) ]
                        , argTypes |> List.map (viewType urlBuilder)
                        ]
                    )

        Type.Tuple _ elems ->
            let
                elemsView =
                    elems
                        |> List.map (viewType urlBuilder)
                        |> List.intersperse (text ", ")
                        |> row []
            in
            row [] [ text "( ", elemsView, text " )" ]

        Type.Record _ fields ->
            let
                fieldsView =
                    fields
                        |> List.map
                            (\field ->
                                row [] [ text (Name.toCamelCase field.name), text " : ", viewType urlBuilder field.tpe ]
                            )
                        |> List.intersperse (text ", ")
                        |> row []
            in
            row [] [ text "{ ", fieldsView, text " }" ]

        Type.ExtensibleRecord _ varName fields ->
            let
                fieldsView =
                    fields
                        |> List.map
                            (\field ->
                                row [] [ text (Name.toCamelCase field.name), text " : ", viewType urlBuilder field.tpe ]
                            )
                        |> List.intersperse (text ", ")
                        |> row []
            in
            row [] [ text "{ ", text (Name.toCamelCase varName), text " | ", fieldsView, text " }" ]

        Type.Function _ argType returnType ->
            row [] [ viewType urlBuilder argType, text " -> ", viewType urlBuilder returnType ]

        Type.Unit _ ->
            text "()"
