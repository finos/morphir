package morphir.classic.ir

enum Literal:
    case BoolLiteral(value: Boolean)
    case CharLiteral(value: Char)
    case StringLiteral(value: String)
    case WholeNumberLiteral(value: Long)
    case FloatLiteral(value: Double)
    case DecimalLiteral(value: BigDecimal)