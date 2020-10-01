module Morphir.IR.Type.Type exposing (..)

import AssocList as Dict exposing (Dict)
import Morphir.IR.FQName exposing (FQName)
import Morphir.IR.Name exposing (Name)
import Morphir.IR.SDK.Basics as Basics
import Morphir.IR.SDK.Char as Char
import Morphir.IR.SDK.Common as SDK
import Morphir.IR.SDK.String as String
import Morphir.IR.Source as Source
import Morphir.IR.Type.Error as Error
import Morphir.IR.Type.UnionFind as UnionFind
import Morphir.IR.Value as Value


type Constraint
    = CTrue
    | CSaveTheEnvironment
    | CEqual Source.Region Error.Category Type (Error.Expected Type)
    | CLocal Source.Region Name (Error.Expected Type)
    | CForeign Source.Region Name (Value.Specification ()) (Error.Expected Type)
    | CPattern Source.Region Error.PCategory Type (Error.PExpected Type)
    | CAnd (List Constraint)
    | CLet
        { rigidVars : List Variable
        , flexVars : List Variable
        , header : Dict Name (Source.Located Type)
        , headerCon : Constraint
        , bodyCon : Constraint
        }


type alias Variable =
    UnionFind.Point Descriptor


type FlatType
    = App1 FQName (List Variable)
    | Fun1 Variable Variable
    | EmptyRecord1
    | Record1 (Dict Name Variable) Variable
    | Unit1
    | Tuple1 Variable Variable (Maybe Variable)


type Type
    = PlaceHolder Name
    | AliasN FQName (List ( Name, Type )) Type
    | VarN Variable
    | AppN FQName (List Type)
    | FunN Type Type
    | EmptyRecordN
    | RecordN (Dict Name Type) Type
    | UnitN
    | TupleN (List Type)


type alias Descriptor =
    { content : Content
    , rank : Int
    , mark : Mark
    , copy : Maybe Variable
    }


type Content
    = FlexVar (Maybe Name)
    | FlexSuper SuperType (Maybe Name)
    | RigidVar Name
    | RigidSuper SuperType Name
    | Structure FlatType
    | Alias FQName (List ( Name, Variable )) Variable
    | Error


type SuperType
    = Number
    | Comparable
    | Appendable
    | CompAppend


makeDescriptor : Content -> Descriptor
makeDescriptor content =
    Descriptor content noRank noMark Nothing



-- RANKS


noRank : Int
noRank =
    0


outermostRank : Int
outermostRank =
    1



-- MARKS


type Mark
    = Mark Int


noMark : Mark
noMark =
    Mark 2


occursMark : Mark
occursMark =
    Mark 1


getVarNamesMark : Mark
getVarNamesMark =
    Mark 0


nextMark : Mark -> Mark
nextMark (Mark mark) =
    Mark (mark + 1)



-- MAKE FLEX VARIABLES


mkFlexVar : Variable
mkFlexVar =
    UnionFind.fresh flexVarDescriptor


flexVarDescriptor : Descriptor
flexVarDescriptor =
    makeDescriptor unnamedFlexVar


unnamedFlexVar : Content
unnamedFlexVar =
    FlexVar Nothing



-- MAKE NAMED VARIABLES


nameToFlex : Name -> Variable
nameToFlex name =
    UnionFind.fresh
        (makeDescriptor
            (case toSuper name of
                Just superName ->
                    FlexSuper superName (Just name)

                Nothing ->
                    FlexVar (Just name)
            )
        )


nameToRigid : Name -> Variable
nameToRigid name =
    UnionFind.fresh
        (makeDescriptor
            (case toSuper name of
                Just superName ->
                    RigidSuper superName name

                Nothing ->
                    RigidVar name
            )
        )


toSuper : Name -> Maybe SuperType
toSuper name =
    if (name |> List.head) == Just "number" then
        Just Number

    else if (name |> List.head) == Just "comparable" then
        Just Comparable

    else if (name |> List.head) == Just "appendable" then
        Just Appendable

    else if (name |> List.head) == Just "compappend" then
        Just CompAppend

    else
        Nothing


int : Type
int =
    AppN (SDK.toFQName Basics.moduleName "Int") []


float : Type
float =
    AppN (SDK.toFQName Basics.moduleName "Float") []


char : Type
char =
    AppN (SDK.toFQName Char.moduleName "Char") []


string : Type
string =
    AppN (SDK.toFQName String.moduleName "String") []


bool : Type
bool =
    AppN (SDK.toFQName Basics.moduleName "Bool") []


never : Type
never =
    AppN (SDK.toFQName Basics.moduleName "Never") []
