module Morphir.TypeScript.AST exposing (..)

{-| This module contains the TypeScript AST (Abstract Syntax Tree). The purpose of this AST is to make it easier to
generate valid TypeScript source code and to separate the language syntax from low-level formatting concerns. We use
this AST as the output of the TypeScript backend and also as the input of the pretty-printer that turns it into the
final text representation.

The AST is maintained manually and it does not have to cover the whole language. We focus on the parts of the language
that we use in the backend.

@docs TypeDef, TypeExp, FieldDef

-}

import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)


{-| -}
type alias CompilationUnit =
    { dirPath : List String
    , fileName : String
    , imports : List ImportDeclaration
    , typeDefs : List TypeDef
    }


{-| Represents either a public or a private entity
-}
type Privacy
    = Public
    | Private


{-| (packagePath, modulePath).

Represents the path to a module. Used in various ways to produce either a path
to a module file, or a reference to that module's namespace. (eg in imports)

This has two components, the package path and the module path.
(Note: this is different from a Morphir Fully Qualified Name, which has three
components: package path, module path AND a local name).

-}
type alias NamespacePath =
    ( Path, Path )


{-| Generate a unique identifier for the given namespace, for private use.
-}
namespaceNameFromPackageAndModule : Path -> Path -> String
namespaceNameFromPackageAndModule packagePath modulePath =
    (packagePath ++ modulePath)
        |> List.map Name.toTitleCase
        |> String.join "_"


type alias CallExpression =
    { function : Expression
    , arguments : List Expression
    }


type Expression
    = ArrayLiteralExpression (List Expression)
    | Call CallExpression
    | Identifier String
    | IntLiteralExpression Int
    | IndexedExpression
        { object : Expression
        , index : Expression
        }
    | MemberExpression
        { object : Expression
        , member : Expression
        }
    | NewExpression
        { constructor : String
        , arguments : List Expression
        }
    | NullLiteral
    | ObjectLiteralExpression { properties : List ( String, Expression ) }
    | StringLiteralExpression String


emptyObject : Expression
emptyObject =
    ObjectLiteralExpression { properties = [] }


type FunctionScope
    = ModuleFunction
    | ClassMemberFunction
    | ClassStaticFunction


type alias Parameter =
    { modifiers : List String
    , name : String
    , typeAnnotation : Maybe TypeExp
    }


parameter : List String -> String -> Maybe TypeExp -> Parameter
parameter modifiers name typeAnnotation =
    { modifiers = modifiers
    , name = name
    , typeAnnotation = typeAnnotation
    }


type Statement
    = FunctionDeclaration
        { name : String
        , typeVariables : List TypeExp
        , returnType : Maybe TypeExp
        , scope : FunctionScope
        , parameters : List Parameter
        , body : List Statement
        , privacy : Privacy
        }
    | LetStatement Expression (Maybe TypeExp) Expression
    | AssignmentStatement Expression (Maybe TypeExp) Expression
    | ExpressionStatement Expression
    | ReturnStatement Expression
    | SwitchStatement Expression (List ( Expression, List Statement ))


{-| Represents a type definition.
-}
type TypeDef
    = Namespace
        { name : String
        , privacy : Privacy
        , content : List TypeDef
        }
    | TypeAlias
        { name : String
        , doc : String
        , privacy : Privacy
        , variables : List TypeExp
        , typeExpression : TypeExp
        , decoder : Maybe Statement
        , encoder : Maybe Statement
        }
    | VariantClass
        { name : String
        , privacy : Privacy
        , variables : List TypeExp
        , body : List Statement
        , constructor : Maybe Statement
        , decoder : Maybe Statement
        , encoder : Maybe Statement
        , typeExpressions : List TypeExp -- for collecting import refs
        }
    | ImportAlias
        { name : String
        , privacy : Privacy
        , namespacePath : NamespacePath
        }


{-| A type expression represents the right-hand side of a type annotation or a type alias.

The structure follows the documentation here:
<https://www.typescriptlang.org/docs/handbook/2/everyday-types.html#the-primitives-string-number-and-boolean>

Only a small subset of the type-system is currently implemented.

-}
type TypeExp
    = Any
    | Boolean
    | FunctionTypeExp (List Parameter) TypeExp
    | List TypeExp {- Represents a Morphir 'List' type, as a Typescript 'Array' type -}
    | LiteralString String
    | Map TypeExp TypeExp
    | Number
    | Object ObjectExp
    | String
    | Tuple (List TypeExp)
    | TypeRef FQName (List TypeExp)
    | Union (List TypeExp)
    | Variable String
    | Nullable TypeExp
    | UnhandledType String


{-| Represents an object expression (or interface definition) as a list of name-and-type pairs.
-}
type alias ObjectExp =
    List ( String, TypeExp )


type alias ImportDeclaration =
    { importClause : String
    , moduleSpecifier : String
    }
