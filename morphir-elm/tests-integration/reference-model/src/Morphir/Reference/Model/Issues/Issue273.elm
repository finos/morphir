module Morphir.Reference.Model.Issues.Issue273 exposing (create)


type alias MyRecord =
    { foo : String
    }


create : MyRecord
create =
    { foo = "Bar"
    }
