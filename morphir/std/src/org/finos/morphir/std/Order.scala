package org.finos.morphir.std

enum Order(val value: Int):
  case LessThan    extends Order(-1)
  case EqualTo     extends Order(0)
  case GreaterThan extends Order(1)

object Order:
  def fromInt(i: Int): Order = i match
    case x if x < 0 => LessThan
    case 0          => EqualTo
    case _          => GreaterThan

  // given Conversion[Order, Int] = _.value
