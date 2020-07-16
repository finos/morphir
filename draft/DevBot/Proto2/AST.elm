module SlateX.DevBot.Proto2.AST exposing (..)


type alias ProtoFile =
    { decls : List Decl 
    }


type Decl
    = Message MessageDecl
    | Enum EnumDecl


type alias MessageDecl =
    { name : String
    , members : List MemberDecl
    }


type MemberDecl 
    = Field FieldDecl
    | OneOf OneOfDecl


type alias FieldDecl =
    { rule : FieldRule
    , tpe : FieldType 
    , name : String
    , number : Int
    , comment : Maybe String
    }


type FieldRule
    = Required
    | Optional
    | Repeated


type FieldType
    = TypeRef String
    | Double
    | Float
    | Int32
    | Int64
    | Bool
    | String
    | Bytes


type alias OneOfDecl =
    { name : String
    , fields : List OneOfFieldDecl
    }


type alias OneOfFieldDecl =
    { tpe : FieldType 
    , name : String
    , number : Int
    }


type alias EnumDecl =
    { name : String
    , values : List ( String, Int )
    }
