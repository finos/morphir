package morphir.ir

/** Generated based on IR.QName
*/
object QName{

  final case class QName(
    arg1: morphir.ir.Path.Path,
    arg2: morphir.ir.Name.Name
  ){}
  
  def fromName(
    modulePath: morphir.ir.Path.Path
  )(
    localName: morphir.ir.Name.Name
  ): morphir.ir.QName.QName =
    (morphir.ir.QName.QName(
      modulePath,
      localName
    ) : morphir.ir.QName.QName)
  
  def fromString(
    qNameString: morphir.sdk.String.String
  ): morphir.sdk.Maybe.Maybe[morphir.ir.QName.QName] =
    morphir.sdk.String.split(""":""")(qNameString) match {
      case packageNameString :: localNameString :: Nil => 
        (morphir.sdk.Maybe.Just((morphir.ir.QName.QName(
          morphir.ir.Path.fromString(packageNameString),
          morphir.ir.Name.fromString(localNameString)
        ) : morphir.ir.QName.QName)) : morphir.sdk.Maybe.Maybe[morphir.ir.QName.QName])
      case _ => 
        (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.ir.QName.QName])
    }
  
  def fromTuple: ((morphir.ir.Path.Path, morphir.ir.Name.Name)) => morphir.ir.QName.QName =
    ({
      case (m, l) => 
        (morphir.ir.QName.QName(
          m,
          l
        ) : morphir.ir.QName.QName)
    } : ((morphir.ir.Path.Path, morphir.ir.Name.Name)) => morphir.ir.QName.QName)
  
  def getLocalName: morphir.ir.QName.QName => morphir.ir.Name.Name =
    ({
      case morphir.ir.QName.QName(_, localName) => 
        localName
    } : morphir.ir.QName.QName => morphir.ir.Name.Name)
  
  def getModulePath: morphir.ir.QName.QName => morphir.ir.Path.Path =
    ({
      case morphir.ir.QName.QName(modulePath, _) => 
        modulePath
    } : morphir.ir.QName.QName => morphir.ir.Path.Path)
  
  def _toString: morphir.ir.QName.QName => morphir.sdk.String.String =
    ({
      case morphir.ir.QName.QName(moduleName, localName) => 
        morphir.sdk.String.join(""":""")(morphir.sdk.List(
          morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(moduleName),
          morphir.ir.Name.toCamelCase(localName)
        ))
    } : morphir.ir.QName.QName => morphir.sdk.String.String)
  
  def toTuple: morphir.ir.QName.QName => (morphir.ir.Path.Path, morphir.ir.Name.Name) =
    ({
      case morphir.ir.QName.QName(m, l) => 
        (m, l)
    } : morphir.ir.QName.QName => (morphir.ir.Path.Path, morphir.ir.Name.Name))

}