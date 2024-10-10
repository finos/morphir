package morphir.ir

/** Generated based on IR.FQName
*/
object FQName{

  type FQName = (morphir.ir.Path.Path, morphir.ir.Path.Path, morphir.ir.Name.Name)
  
  def fQName(
    packagePath: morphir.ir.Path.Path
  )(
    modulePath: morphir.ir.Path.Path
  )(
    localName: morphir.ir.Name.Name
  ): morphir.ir.FQName.FQName =
    (packagePath, modulePath, localName)
  
  def fqn(
    packageName: morphir.sdk.String.String
  )(
    moduleName: morphir.sdk.String.String
  )(
    localName: morphir.sdk.String.String
  ): morphir.ir.FQName.FQName =
    morphir.ir.FQName.fQName(morphir.ir.Path.fromString(packageName))(morphir.ir.Path.fromString(moduleName))(morphir.ir.Name.fromString(localName))
  
  def fromQName(
    packagePath: morphir.ir.Path.Path
  )(
    qName: morphir.ir.QName.QName
  ): morphir.ir.FQName.FQName =
    (packagePath, morphir.ir.QName.getModulePath(qName), morphir.ir.QName.getLocalName(qName))
  
  def fromString(
    fqNameString: morphir.sdk.String.String
  )(
    splitter: morphir.sdk.String.String
  ): morphir.ir.FQName.FQName =
    morphir.sdk.String.split(splitter)(fqNameString) match {
      case moduleNameString :: packageNameString :: localNameString :: Nil => 
        (morphir.ir.Path.fromString(moduleNameString), morphir.ir.Path.fromString(packageNameString), morphir.ir.Name.fromString(localNameString))
      case _ => 
        (morphir.sdk.List(morphir.sdk.List(
        
        )), morphir.sdk.List(
        
        ), morphir.sdk.List(
        
        ))
    }
  
  def fromStringStrict(
    fqNameString: morphir.sdk.String.String
  )(
    separator: morphir.sdk.String.String
  ): morphir.sdk.Result.Result[morphir.sdk.String.String, morphir.ir.FQName.FQName] =
    morphir.sdk.String.split(separator)(fqNameString) match {
      case moduleNameString :: packageNameString :: localNameString :: Nil => 
        (morphir.sdk.Result.Ok((morphir.ir.Path.fromString(moduleNameString), morphir.ir.Path.fromString(packageNameString), morphir.ir.Name.fromString(localNameString))) : morphir.sdk.Result.Result[morphir.sdk.String.String, morphir.ir.FQName.FQName])
      case parts => 
        (morphir.sdk.Result.Err(morphir.sdk.String.concat(morphir.sdk.List(
          """A fully-qualified name needs to have 3 parts: a package name, a module name and a local name. """,
          """I found """,
          morphir.sdk.String.fromInt(morphir.sdk.List.length(parts)),
          """ parts by splitting '""",
          fqNameString,
          """' using '""",
          separator,
          """' as the separator."""
        ))) : morphir.sdk.Result.Result[morphir.sdk.String.String, morphir.ir.FQName.FQName])
    }
  
  def getLocalName: morphir.ir.FQName.FQName => morphir.ir.Name.Name =
    ({
      case (_, _, l) => 
        l
    } : morphir.ir.FQName.FQName => morphir.ir.Name.Name)
  
  def getModulePath: morphir.ir.FQName.FQName => morphir.ir.Path.Path =
    ({
      case (_, m, _) => 
        m
    } : morphir.ir.FQName.FQName => morphir.ir.Path.Path)
  
  def getPackagePath: morphir.ir.FQName.FQName => morphir.ir.Path.Path =
    ({
      case (p, _, _) => 
        p
    } : morphir.ir.FQName.FQName => morphir.ir.Path.Path)
  
  def _toString: morphir.ir.FQName.FQName => morphir.sdk.String.String =
    ({
      case (p, m, l) => 
        morphir.sdk.String.join(""":""")(morphir.sdk.List(
          morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(p),
          morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(m),
          morphir.ir.Name.toCamelCase(l)
        ))
    } : morphir.ir.FQName.FQName => morphir.sdk.String.String)

}