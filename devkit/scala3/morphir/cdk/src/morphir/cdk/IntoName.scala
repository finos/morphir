package morphir.cdk

trait IntoName[-A]:

  extension (a: A) def intoName: Name

object IntoName:
  private val pattern = """([a-zA-Z][a-z]*|[0-9]+)""".r

  given IntoName[String] with
    extension (str: String)
      def intoName: Name = Name(
        pattern.findAllIn(str).toList.map(_.toLowerCase())
      )

  def fromString(str: String)(using IntoName[String]): Name = str.intoName

  def intoName[Self](self: Self)(using intoName: IntoName[Self]): Name =
    self.intoName

  private[morphir] def wrap(value: List[String]): Name = Name(value)

  private[morphir] def wrap(value: Array[String]): Name = Name(value.toList)
