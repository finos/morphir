{-
Copyright 2020 Morgan Stanley

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}


module SlateX.DevBot.Scala.SlateXToScala.Values exposing (..)



import Set
import SlateX.AST.Type as T
import SlateX.AST.Value as V
import SlateX.AST.Value.Annotated as A
import SlateX.DevBot.Scala.AST as S
import SlateX.DevBot.Scala.SlateXToScala.Report as Report
import SlateX.Mapping.Naming as Naming
import SlateX.DevBot.Scala.SlateXToScala.CoreValues as SlateXCore
import SlateX.DevBot.Scala.ReservedWords as ReservedWords


mapExp : A.Exp (Result String T.Exp) -> S.Value
mapExp topExp =
    case topExp of
        A.Literal lit typeOrError ->
            mapLit typeOrError lit

        A.Variable name typeOrError ->
            S.Var (name |> Naming.toCamelCase)

        A.Reference ( [ [ "slate", "x" ], [ "core" ], moduleName ], funName ) typeOrError ->
            SlateXCore.mapReference
                (moduleName |> Naming.toTitleCase)
                (funName |> Naming.toCamelCase)    

        A.Reference ( modulePath, localName ) typeOrError ->
            let
                ( packagePath, moduleName ) =
                    case modulePath |> List.reverse of
                        [] ->
                            -- this should never happen
                            ( [], [] )

                        lastName :: reversePackagePath ->
                            ( reversePackagePath |> List.reverse, lastName )

                scalaName =
                    localName |> Naming.toCamelCase

                normalizedName =
                    if ReservedWords.reservedValueNames |> Set.member scalaName then
                        "_" ++ scalaName
                    else
                        scalaName    
            in
            S.Ref 
                ((packagePath |> List.map (Naming.toCamelCase >> String.toLower)) ++ [ moduleName |> Naming.toTitleCase ])
                normalizedName

        A.FieldAccess targetExp fieldName typeOrError ->
            S.Select (targetExp |> mapExp) (fieldName |> Naming.toCamelCase)

        A.FieldAccessFunction fieldName typeOrError ->
            S.Select S.Wildcard (fieldName |> Naming.toCamelCase)

        A.Apply funExp argExp typeOrError as apply ->
            let
                flattenApply e =
                    case e of
                        A.Apply f a _ ->
                            let
                                ( bf, ars ) =
                                    flattenApply f
                            in
                            ( bf, ars ++ [ a ] )

                        _ ->
                            ( e, [] )            

                ( bottomFun, args ) =
                    flattenApply apply
            in
            case bottomFun of
                -- This is an apply on a slatex-core function so handle it in a separate module
                A.Reference ( [ [ "slate", "x" ], [ "core" ], moduleName ], funName ) _ ->
                    SlateXCore.mapApply
                        (moduleName |> Naming.toTitleCase)
                        (funName |> Naming.toCamelCase)
                        (args |> List.map mapExp)

                -- This is a constructor invocation so do not curry
                A.Constructor ( [ [ "slate", "x" ], [ "core" ], moduleName ], typeName ) _ ->
                    S.Apply
                        (SlateXCore.mapConstructor 
                            (moduleName |> Naming.toTitleCase)
                            (typeName |> Naming.toTitleCase)
                        )
                        (args
                            |> List.map (mapExp >> S.ArgValue Nothing)
                        )

                -- This is a constructor invocation so do not curry
                A.Constructor ( modulePath, localName ) _ ->
                    S.Apply
                        (S.Ref 
                            (modulePath |> List.map (Naming.toCamelCase >> String.toLower)) 
                            (localName |> Naming.toTitleCase)
                        )    
                        (args
                            |> List.map (mapExp >> S.ArgValue Nothing)
                        )

                _ ->
                    S.Apply (funExp |> mapExp) [ argExp |> mapExp |> S.ArgValue Nothing ]

        A.Lambda argPattern bodyExp _ ->
            case argPattern of
                A.MatchAny _ ->
                    S.Lambda [ "_" ]
                        (bodyExp |> mapExp)

                A.MatchAnyAlias name _ ->
                    S.Lambda [ name |> Naming.toCamelCase ]
                        (bodyExp |> mapExp)

                _ ->
                    S.MatchCases [ ( argPattern |> mapPattern, bodyExp |> mapExp ) ]        

        A.LetExp _ _ _ typeOrError ->
            let
                flattenLet exp =
                    case exp of
                        A.LetExp bindingPattern bindingExp inExp _ ->
                            let
                                ( nestedBindings, bottom ) =
                                    flattenLet inExp
                            in
                            ( ( bindingPattern, bindingExp ) :: nestedBindings, bottom )

                        other ->
                            ( [], other )

                ( bindings, bottomInExp ) =
                    flattenLet topExp                
            in
            S.LetBlock
                (bindings
                    |> List.map
                        (\( bindingPattern, bindingExp ) ->
                            ( bindingPattern |> mapPattern, bindingExp |> mapExp )
                        )
                )
                (bottomInExp |> mapExp)

        A.IfExp condExp trueExp falseExp typeOrError ->
            S.IfElse
                (condExp |> mapExp)
                (trueExp |> mapExp)
                (falseExp |> mapExp)

        A.CaseExp ofExp cases typeOrError ->
            S.Match (ofExp |> mapExp)
                (S.MatchCases
                    (cases
                        |> List.map
                            (\( casePattern, caseExp ) ->
                                ( casePattern |> mapPattern, caseExp |> mapExp )
                            )
                    )
                )

        A.Constructor ( [ [ "slate", "x" ], [ "core" ], moduleName ], typeName ) typeOrError ->
            SlateXCore.mapConstructor 
                (moduleName |> Naming.toTitleCase)
                (typeName |> Naming.toTitleCase)

        A.Constructor ( modulePath, localName ) typeOrError ->
            S.Ref 
                (modulePath |> List.map (Naming.toCamelCase >> String.toLower)) 
                (localName |> Naming.toTitleCase)

        A.Tuple elemExps typeOrError ->
            S.Tuple (elemExps |> List.map mapExp)

        A.List itemExps typeOrError ->
            case itemExps of
                [] ->
                    S.Ref [ "scala" ] "Nil"

                _ ->    
                    S.Apply (S.Ref [ "scala" ] "List")
                        (itemExps |> List.map (mapExp >> S.ArgValue Nothing))

        A.Record fields typeOrError ->
            case typeOrError of
                -- If this is a named record type it translates to a case class in Scala so we can invoke the constructor
                Ok (T.Constructor ( modulePath, localName ) _) ->
                    S.Apply
                        (S.Ref (modulePath |> List.map (Naming.toCamelCase >> String.toLower)) (localName |> Naming.toTitleCase))
                        (fields
                            |> List.map
                                (\( fieldName, fieldValue ) ->
                                    S.ArgValue
                                        (Just (fieldName |> Naming.toCamelCase))
                                        (mapExp fieldValue)
                                )
                        )

                _ ->
                    Report.todoValue (Debug.toString typeOrError)

        A.RecordUpdate targetExp fieldsToUpdate typeOrError ->
            S.Apply
                (S.Select (targetExp |> mapExp) "copy")
                (fieldsToUpdate
                    |> List.map
                        (\( fieldName, fieldValue ) ->
                            S.ArgValue
                                (Just (fieldName |> Naming.toCamelCase))
                                (mapExp fieldValue)
                        )
                )


mapLit : (Result String T.Exp) -> V.Lit -> S.Value
mapLit typeOrError lit =
    case lit of
        V.BooleanLit bool ->
            S.Literal <| S.BooleanLit bool

        V.CharacterLit char ->
            S.Literal <| S.CharacterLit char

        V.StringLit string ->
            S.Literal <| S.StringLit string

        V.IntegerLit int ->
            case typeOrError of
                Ok (T.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "basics" ] ], [ "decimal" ] ) []) ->
                    S.Apply (S.Ref [ "scala", "math" ] "BigDecimal")
                        [ S.ArgValue Nothing (S.Literal (S.IntegerLit int))
                        ]

                _ ->        
                    S.Literal <| S.IntegerLit int 

        V.FloatLit float ->
            case typeOrError of
                Ok (T.Constructor ( [ [ "slate", "x" ], [ "core" ], [ "basics" ] ], [ "decimal" ] ) []) ->
                    S.Apply (S.Ref [ "scala", "math" ] "BigDecimal")
                        [ S.ArgValue Nothing (S.Literal (S.StringLit (Debug.toString float)))
                        ]

                _ ->        
                    S.Literal <| S.FloatLit float


mapPattern : A.Pattern (Result String T.Exp) -> S.Pattern
mapPattern pattern =
    case pattern of
        A.MatchAny typeOrError ->
            S.WildcardMatch

        A.MatchAnyAlias name typeOrError ->
            S.AliasMatch (name |> Naming.toCamelCase)

        A.MatchLiteral lit typeOrError ->
            case mapLit typeOrError lit of
                S.Literal l ->
                    S.LiteralMatch l

                other ->
                    Report.todoPattern ("Matching not supported on: " ++ Debug.toString other)    

        A.MatchConstructor ( [ [ "slate", "x" ], [ "core" ], moduleName ], typeName ) argPatterns typeOrError ->
            SlateXCore.mapMatchConstructor 
                (moduleName |> Naming.toTitleCase)
                (typeName |> Naming.toTitleCase)
                (argPatterns
                    |> List.map mapPattern
                )

        A.MatchConstructor ( modulePath, localName ) argPatterns typeOrError ->
            S.UnapplyMatch 
                (modulePath |> List.map (Naming.toCamelCase >> String.toLower))                 
                (localName |> Naming.toTitleCase)
                (argPatterns
                    |> List.map mapPattern
                )

        A.MatchTuple elemPatterns _ ->
            S.TupleMatch (elemPatterns |> List.map mapPattern)

        A.MatchListItems itemPatterns typeOrError ->
            Report.todoPattern (Debug.toString pattern)

        A.MatchListHeadTail headPattern tailPattern typeOrError ->
            Report.todoPattern (Debug.toString pattern)

        A.MatchRecordFields fieldNames typeOrError ->
            Report.todoPattern (Debug.toString pattern)
