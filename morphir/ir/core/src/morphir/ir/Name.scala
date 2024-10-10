package morphir.ir

/** Generated based on IR.Name
*/
object Name{

  type Name = morphir.sdk.List.List[morphir.sdk.String.String]
  
  def capitalize(
    string: morphir.sdk.String.String
  ): morphir.sdk.String.String =
    morphir.sdk.String.uncons(string) match {
      case morphir.sdk.Maybe.Just((headChar, tailString)) => 
        morphir.sdk.String.cons(morphir.sdk.Char.toUpper(headChar))(tailString)
      case morphir.sdk.Maybe.Nothing => 
        string
    }
  
  def fromList(
    words: morphir.sdk.List.List[morphir.sdk.String.String]
  ): morphir.ir.Name.Name =
    words
  
  def fromString(
    string: morphir.sdk.String.String
  ): morphir.ir.Name.Name = {
    val wordPattern: morphir.sdk.Regex.Regex = morphir.sdk.Maybe.withDefault(morphir.sdk.Regex.never)(morphir.sdk.Regex.fromString("""([a-zA-Z][a-z]*|[0-9]+)"""))
    
    morphir.ir.Name.fromList(morphir.sdk.List.map(morphir.sdk.String.toLower)(morphir.sdk.List.map(((x: morphir.sdk.Regex.Match) =>
      x._match))(morphir.sdk.Regex.find(wordPattern)(string))))
  }
  
  def toCamelCase(
    name: morphir.ir.Name.Name
  ): morphir.sdk.String.String =
    morphir.ir.Name.toList(name) match {
      case Nil => 
        """"""
      case head :: tail => 
        morphir.sdk.String.join("""""")(morphir.sdk.List.cons(head)(morphir.sdk.List.map(morphir.ir.Name.capitalize)(tail)))
    }
  
  def toHumanWords(
    name: morphir.ir.Name.Name
  ): morphir.sdk.List.List[morphir.sdk.String.String] = {
    val words: morphir.sdk.List.List[morphir.sdk.String.String] = morphir.ir.Name.toList(name)
    
    def join(
      abbrev: morphir.sdk.List.List[morphir.sdk.String.String]
    ): morphir.sdk.String.String =
      morphir.sdk.String.toUpper(morphir.sdk.String.join("""""")(abbrev))
    
    {
      def process(
        prefix: morphir.sdk.List.List[morphir.sdk.String.String]
      )(
        abbrev: morphir.sdk.List.List[morphir.sdk.String.String]
      )(
        suffix: morphir.sdk.List.List[morphir.sdk.String.String]
      ): morphir.sdk.List.List[morphir.sdk.String.String] =
        suffix match {
          case Nil => 
            if (morphir.sdk.List.isEmpty(abbrev)) {
              prefix
            } else {
              morphir.sdk.List.append(prefix)(morphir.sdk.List(join(abbrev)))
            }
          case first :: rest => 
            if (morphir.sdk.Basics.equal(morphir.sdk.String.length(first))(morphir.sdk.Basics.Int(1))) {
              process(prefix)(morphir.sdk.List.append(abbrev)(morphir.sdk.List(first)))(rest)
            } else {
              abbrev match {
                case Nil => 
                  process(morphir.sdk.List.append(prefix)(morphir.sdk.List(first)))(morphir.sdk.List(
                  
                  ))(rest)
                case _ => 
                  process(morphir.sdk.List.append(prefix)(morphir.sdk.List(
                    join(abbrev),
                    first
                  )))(morphir.sdk.List(
                  
                  ))(rest)
              }
            }
        }
      
      name match {
        case word :: Nil => 
          if (morphir.sdk.Basics.equal(morphir.sdk.String.length(word))(morphir.sdk.Basics.Int(1))) {
            name
          } else {
            process(morphir.sdk.List(
            
            ))(morphir.sdk.List(
            
            ))(words)
          }
        case _ => 
          process(morphir.sdk.List(
          
          ))(morphir.sdk.List(
          
          ))(words)
      }
    }
  }
  
  def toHumanWordsTitle(
    name: morphir.ir.Name.Name
  ): morphir.sdk.List.List[morphir.sdk.String.String] =
    morphir.ir.Name.toHumanWords(name) match {
      case firstWord :: rest => 
        morphir.sdk.List.cons(morphir.ir.Name.capitalize(firstWord))(rest)
      case Nil => 
        morphir.sdk.List(
        
        )
    }
  
  def toList(
    words: morphir.ir.Name.Name
  ): morphir.sdk.List.List[morphir.sdk.String.String] =
    words
  
  def toSnakeCase(
    name: morphir.ir.Name.Name
  ): morphir.sdk.String.String =
    morphir.sdk.String.join("""_""")(morphir.ir.Name.toHumanWords(name))
  
  def toTitleCase(
    name: morphir.ir.Name.Name
  ): morphir.sdk.String.String =
    morphir.sdk.String.join("""""")(morphir.sdk.List.map(morphir.ir.Name.capitalize)(morphir.ir.Name.toList(name)))

}