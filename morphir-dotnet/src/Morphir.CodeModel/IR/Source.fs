module Morphir.IR.Source

type Located<'A> = At of Region * 'A
and Region = { Start: Location; End: Location }
and Location = { Row: int64; Column: int64 }
