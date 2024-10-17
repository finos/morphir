package morphir.ir

/** Generated based on IR.Literal
*/
object Literal{

  sealed trait Literal {
  
    
  
  }
  
  object Literal{
  
    final case class BoolLiteral(
      arg1: morphir.sdk.Basics.Bool
    ) extends morphir.ir.Literal.Literal{}
    
    final case class CharLiteral(
      arg1: morphir.sdk.Char.Char
    ) extends morphir.ir.Literal.Literal{}
    
    final case class DecimalLiteral(
      arg1: morphir.sdk.Decimal.Decimal
    ) extends morphir.ir.Literal.Literal{}
    
    final case class FloatLiteral(
      arg1: morphir.sdk.Basics.Float
    ) extends morphir.ir.Literal.Literal{}
    
    final case class StringLiteral(
      arg1: morphir.sdk.String.String
    ) extends morphir.ir.Literal.Literal{}
    
    final case class WholeNumberLiteral(
      arg1: morphir.sdk.Basics.Int
    ) extends morphir.ir.Literal.Literal{}
  
  }
  
  val BoolLiteral: morphir.ir.Literal.Literal.BoolLiteral.type  = morphir.ir.Literal.Literal.BoolLiteral
  
  val CharLiteral: morphir.ir.Literal.Literal.CharLiteral.type  = morphir.ir.Literal.Literal.CharLiteral
  
  val DecimalLiteral: morphir.ir.Literal.Literal.DecimalLiteral.type  = morphir.ir.Literal.Literal.DecimalLiteral
  
  val FloatLiteral: morphir.ir.Literal.Literal.FloatLiteral.type  = morphir.ir.Literal.Literal.FloatLiteral
  
  val StringLiteral: morphir.ir.Literal.Literal.StringLiteral.type  = morphir.ir.Literal.Literal.StringLiteral
  
  val WholeNumberLiteral: morphir.ir.Literal.Literal.WholeNumberLiteral.type  = morphir.ir.Literal.Literal.WholeNumberLiteral
  
  def boolLiteral(
    value: morphir.sdk.Basics.Bool
  ): morphir.ir.Literal.Literal =
    (morphir.ir.Literal.BoolLiteral(value) : morphir.ir.Literal.Literal)
  
  def charLiteral(
    value: morphir.sdk.Char.Char
  ): morphir.ir.Literal.Literal =
    (morphir.ir.Literal.CharLiteral(value) : morphir.ir.Literal.Literal)
  
  def floatLiteral(
    value: morphir.sdk.Basics.Float
  ): morphir.ir.Literal.Literal =
    (morphir.ir.Literal.FloatLiteral(value) : morphir.ir.Literal.Literal)
  
  def intLiteral(
    value: morphir.sdk.Basics.Int
  ): morphir.ir.Literal.Literal =
    (morphir.ir.Literal.WholeNumberLiteral(value) : morphir.ir.Literal.Literal)
  
  def stringLiteral(
    value: morphir.sdk.String.String
  ): morphir.ir.Literal.Literal =
    (morphir.ir.Literal.StringLiteral(value) : morphir.ir.Literal.Literal)

}