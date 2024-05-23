module Morphir.TypeScript.Backend.Imports exposing (getTypeScriptPackagePathAndModuleName, getUniqueImportRefs, makeRelativeImport, renderInternalImport)

import Morphir.File.SourceCode exposing (concat)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Path exposing (Path)
import Morphir.TypeScript.AST as TS


{-| Extracts a directory path (as a sequence of folder name string) and a Module filename (as a
Name object), given a Morphir Package Path and a Morphir Module Path.
-}
getTypeScriptPackagePathAndModuleName : Path -> Path -> ( List String, Name )
getTypeScriptPackagePathAndModuleName packagePath modulePath =
    case modulePath |> List.reverse of
        [] ->
            ( [], [] )

        lastName :: reverseModulePath ->
            ( List.append
                (packagePath |> List.map (Name.toCamelCase >> String.toLower))
                (reverseModulePath |> List.reverse |> List.map (Name.toCamelCase >> String.toLower))
            , lastName
            )


filePathFromTop : TS.NamespacePath -> String
filePathFromTop ( packagePath, modulePath ) =
    getTypeScriptPackagePathAndModuleName packagePath modulePath
        |> (\( typeScriptPackagePath, moduleName ) ->
                concat
                    [ typeScriptPackagePath |> String.join "/"
                    , "/"
                    , moduleName |> Name.toTitleCase
                    ]
           )


makeRelativeImport : List String -> String -> String
makeRelativeImport dirPath modulePathFromTop =
    let
        filePathPrefix : String
        filePathPrefix =
            dirPath
                |> List.map (\_ -> "..")
                |> (\list -> "." :: list)
                |> String.join "/"
    in
    filePathPrefix ++ "/" ++ modulePathFromTop


renderInternalImport : List String -> TS.NamespacePath -> TS.ImportDeclaration
renderInternalImport dirPath ( packagePath, modulePath ) =
    let
        modulePathFromTop =
            ( packagePath, modulePath ) |> filePathFromTop
    in
    { importClause = "{ " ++ TS.namespaceNameFromPackageAndModule packagePath modulePath ++ " }"
    , moduleSpecifier = makeRelativeImport dirPath modulePathFromTop
    }


getUniqueImportRefs : Path -> Path -> TS.TypeDef -> List TS.NamespacePath
getUniqueImportRefs currentPackagePath currentModulePath typeDef =
    typeDef
        |> collectRefsFromTypeDef
        |> List.filter
            (\( packagePath, modulePath ) ->
                packagePath /= currentPackagePath || modulePath /= currentModulePath
            )
        |> List.filter
            (\( packagePath, modulePath ) ->
                packagePath /= [] || modulePath /= []
            )
        |> List.sort
        |> filterUnique


filterUnique : List a -> List a
filterUnique inputList =
    let
        incrementalFilterUnique : a -> List a -> List a
        incrementalFilterUnique element shorterList =
            if List.member element shorterList then
                shorterList

            else
                element :: shorterList
    in
    List.foldr incrementalFilterUnique [] inputList


collectRefsFromTypeDef : TS.TypeDef -> List TS.NamespacePath
collectRefsFromTypeDef typeDef =
    case typeDef of
        TS.Namespace namespace ->
            namespace.content |> List.concatMap collectRefsFromTypeDef

        TS.TypeAlias typeAlias ->
            List.concat
                [ typeAlias.variables |> List.concatMap collectRefsFromTypeExpression
                , typeAlias.typeExpression |> collectRefsFromTypeExpression
                ]

        TS.VariantClass variantClass ->
            (variantClass.variables ++ variantClass.typeExpressions)
                |> List.concatMap collectRefsFromTypeExpression

        TS.ImportAlias importAlias ->
            [ importAlias.namespacePath ]


collectRefsFromTypeExpression : TS.TypeExp -> List TS.NamespacePath
collectRefsFromTypeExpression typeExp =
    case typeExp of
        TS.List subTypeExp ->
            subTypeExp |> collectRefsFromTypeExpression

        TS.Tuple subTypeExpList ->
            subTypeExpList |> List.concatMap collectRefsFromTypeExpression

        TS.Union subTypeExpList ->
            subTypeExpList |> List.concatMap collectRefsFromTypeExpression

        TS.Object fieldList ->
            fieldList |> List.concatMap (\( _, subTypeExp ) -> collectRefsFromTypeExpression subTypeExp)

        TS.TypeRef ( packagePath, modulePath, _ ) subTypeExpList ->
            List.concat
                [ [ ( packagePath, modulePath ) ]
                , subTypeExpList |> List.concatMap collectRefsFromTypeExpression
                ]

        TS.Map keyType valueType ->
            [ keyType, valueType ] |> List.concatMap collectRefsFromTypeExpression

        TS.Nullable subTypeExp ->
            subTypeExp |> collectRefsFromTypeExpression

        _ ->
            []
