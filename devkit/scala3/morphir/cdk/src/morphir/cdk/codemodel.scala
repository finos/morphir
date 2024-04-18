package morphir.cdk

enum Type:
  case Variable(name: Name)

enum Literal:
  case Bool(value: Boolean)
  case Char(value: Char)
  case String(value: String)
  case Decimal(value: BigDecimal)

enum Data:
  case Bool(value: Boolean)
  case Chat(value: Char)
