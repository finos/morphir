package morphir.ir

/** Generated based on IR.Module
*/
object Module{

  final case class Definition[Ta, Va](
    types: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Ta]]]],
    values: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]]],
    doc: morphir.sdk.Maybe.Maybe[morphir.sdk.String.String]
  ){}
  
  type ModuleName = morphir.ir.Path.Path
  
  type QualifiedModuleName = (morphir.ir.Path.Path, morphir.ir.Path.Path)
  
  final case class Specification[Ta](
    types: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Documented.Documented[morphir.ir.Type.Specification[Ta]]],
    values: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Documented.Documented[morphir.ir.Value.Specification[Ta]]],
    doc: morphir.sdk.Maybe.Maybe[morphir.sdk.String.String]
  ){}
  
  def collectReferences[Ta, Va](
    moduleDef: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] =
    morphir.sdk.Set.union(morphir.ir.Module.collectTypeReferences(moduleDef))(morphir.ir.Module.collectValueReferences(moduleDef))
  
  def collectTypeReferences[Ta, Va](
    moduleDef: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] = {
    val typeRefs: morphir.sdk.Set.Set[morphir.ir.FQName.FQName] = morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.map(((typeDef: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Ta]]]) =>
      typeDef.value.value match {
        case morphir.ir.Type.TypeAliasDefinition(_, tpe) => 
          morphir.ir.Type.collectReferences(tpe)
        case morphir.ir.Type.CustomTypeDefinition(_, ctors) => 
          morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.concatMap(((ctorArgs: morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[Ta])]) =>
            morphir.sdk.List.map(({
              case (_, tpe) => 
                morphir.ir.Type.collectReferences(tpe)
            } : ((morphir.ir.Name.Name, morphir.ir.Type.Type[Ta])) => morphir.sdk.Set.Set[morphir.ir.FQName.FQName]))(ctorArgs)))(morphir.sdk.Dict.values(ctors.value)))
      }))(morphir.sdk.Dict.values(moduleDef.types)))
    
    val valueRefs: morphir.sdk.Set.Set[morphir.ir.FQName.FQName] = morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.concatMap(((valueDef: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]]) =>
      morphir.sdk.List.map(morphir.ir.Type.collectReferences[Ta])(morphir.sdk.List.cons(valueDef.value.value.outputType)(morphir.sdk.List.map(({
        case (_, _, tpe) => 
          tpe
      } : ((morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])) => morphir.ir.Type.Type[Ta]))(valueDef.value.value.inputTypes)))))(morphir.sdk.Dict.values(moduleDef.values)))
    
    morphir.sdk.Set.union(typeRefs)(valueRefs)
  }
  
  def collectValueReferences[Ta, Va](
    moduleDef: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] =
    morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.map(((valueDef: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]]) =>
      morphir.ir.Value.collectReferences(valueDef.value.value.body)))(morphir.sdk.Dict.values(moduleDef.values)))
  
  def definitionToSpecification[Ta, Va](
    _def: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.ir.Module.Specification[Ta] =
    morphir.ir.Module.Specification(
      doc = _def.doc,
      types = morphir.sdk.Dict.fromList(morphir.sdk.List.filterMap(({
        case (path, accessControlledType) => 
          morphir.sdk.Maybe.map(((typeDef: morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Ta]]) =>
            (path, morphir.ir.Documented.map(morphir.ir.Type.definitionToSpecification[Ta])(typeDef))))(morphir.ir.AccessControlled.withPublicAccess(accessControlledType))
      } : ((morphir.ir.Name.Name, morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Ta]]])) => morphir.sdk.Maybe.Maybe[(morphir.ir.Name.Name, morphir.ir.Documented.Documented[morphir.ir.Type.Specification[Ta]])]))(morphir.sdk.Dict.toList(_def.types))),
      values = morphir.sdk.Dict.fromList(morphir.sdk.List.filterMap(({
        case (path, accessControlledValue) => 
          morphir.sdk.Maybe.map(((valueDef: morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]) =>
            (path, morphir.ir.Documented.map(morphir.ir.Value.definitionToSpecification[Ta, Va])(valueDef))))(morphir.ir.AccessControlled.withPublicAccess(accessControlledValue))
      } : ((morphir.ir.Name.Name, morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]])) => morphir.sdk.Maybe.Maybe[(morphir.ir.Name.Name, morphir.ir.Documented.Documented[morphir.ir.Value.Specification[Ta]])]))(morphir.sdk.Dict.toList(_def.values)))
    )
  
  def definitionToSpecificationWithPrivate[Ta, Va](
    _def: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.ir.Module.Specification[Ta] =
    morphir.ir.Module.Specification(
      doc = _def.doc,
      types = morphir.sdk.Dict.fromList(morphir.sdk.List.map(({
        case (path, accessControlledType) => 
          (path, morphir.ir.Documented.map(morphir.ir.Type.definitionToSpecificationWithPrivate[Ta])(morphir.ir.AccessControlled.withPrivateAccess(accessControlledType)))
      } : ((morphir.ir.Name.Name, morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Ta]]])) => (morphir.ir.Name.Name, morphir.ir.Documented.Documented[morphir.ir.Type.Specification[Ta]])))(morphir.sdk.Dict.toList(_def.types))),
      values = morphir.sdk.Dict.fromList(morphir.sdk.List.map(({
        case (path, accessControlledValue) => 
          (path, morphir.ir.Documented.map(morphir.ir.Value.definitionToSpecification[Ta, Va])(morphir.ir.AccessControlled.withPrivateAccess(accessControlledValue)))
      } : ((morphir.ir.Name.Name, morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]])) => (morphir.ir.Name.Name, morphir.ir.Documented.Documented[morphir.ir.Value.Specification[Ta]])))(morphir.sdk.Dict.toList(_def.values)))
    )
  
  def dependsOnModules[Ta, Va](
    moduleDef: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.sdk.Set.Set[morphir.ir.Module.QualifiedModuleName] =
    morphir.sdk.Set.map(({
      case (packageName, moduleName, _) => 
        (packageName, moduleName)
    } : ((morphir.ir.Path.Path, morphir.ir.Path.Path, morphir.ir.Name.Name)) => morphir.ir.Module.QualifiedModuleName))(morphir.ir.Module.collectReferences(moduleDef))
  
  def emptyDefinition[Ta, Va]: morphir.ir.Module.Definition[Ta, Va] =
    morphir.ir.Module.Definition(
      doc = (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.sdk.String.String]),
      types = morphir.sdk.Dict.empty,
      values = morphir.sdk.Dict.empty
    )
  
  def emptySpecification[Ta]: morphir.ir.Module.Specification[Ta] =
    morphir.ir.Module.Specification(
      doc = (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.sdk.String.String]),
      types = morphir.sdk.Dict.empty,
      values = morphir.sdk.Dict.empty
    )
  
  def eraseDefinitionAttributes[Ta, Va](
    _def: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.ir.Module.Definition[scala.Unit, scala.Unit] =
    morphir.ir.Module.mapDefinitionAttributes(({
      case _ => 
        {}
    } : Ta => scala.Unit))(({
      case _ => 
        {}
    } : Va => scala.Unit))(_def)
  
  def eraseSpecificationAttributes[Ta](
    spec: morphir.ir.Module.Specification[Ta]
  ): morphir.ir.Module.Specification[scala.Unit] =
    morphir.ir.Module.mapSpecificationAttributes(({
      case _ => 
        {}
    } : Ta => scala.Unit))(spec)
  
  def lookupTypeSpecification[Ta](
    localName: morphir.ir.Name.Name
  )(
    moduleSpec: morphir.ir.Module.Specification[Ta]
  ): morphir.sdk.Maybe.Maybe[morphir.ir.Type.Specification[Ta]] =
    morphir.sdk.Maybe.map(((x: morphir.ir.Documented.Documented[morphir.ir.Type.Specification[Ta]]) =>
      x.value))(morphir.sdk.Dict.get(localName)(moduleSpec.types))
  
  def lookupValueDefinition[Ta, Va](
    localName: morphir.ir.Name.Name
  )(
    moduleDef: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.sdk.Maybe.Maybe[morphir.ir.Value.Definition[Ta, Va]] =
    morphir.sdk.Maybe.map(morphir.sdk.Basics.composeRight(morphir.ir.AccessControlled.withPrivateAccess[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]])(((x: morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]) =>
      x.value)))(morphir.sdk.Dict.get(localName)(moduleDef.values))
  
  def lookupValueSpecification[Ta](
    localName: morphir.ir.Name.Name
  )(
    moduleSpec: morphir.ir.Module.Specification[Ta]
  ): morphir.sdk.Maybe.Maybe[morphir.ir.Value.Specification[Ta]] =
    morphir.sdk.Maybe.map(((x: morphir.ir.Documented.Documented[morphir.ir.Value.Specification[Ta]]) =>
      x.value))(morphir.sdk.Dict.get(localName)(moduleSpec.values))
  
  def mapDefinitionAttributes[Ta, Tb, Va, Vb](
    tf: Ta => Tb
  )(
    vf: Va => Vb
  )(
    _def: morphir.ir.Module.Definition[Ta, Va]
  ): morphir.ir.Module.Definition[Tb, Vb] =
    (morphir.ir.Module.Definition(
      morphir.sdk.Dict.map(({
        case _ => 
          ((typeDef: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Ta]]]) =>
            (morphir.ir.AccessControlled.AccessControlled(
              typeDef.access,
              morphir.ir.Documented.map(morphir.ir.Type.mapDefinitionAttributes(tf))(typeDef.value)
            ) : morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Tb]]]))
      } : morphir.ir.Name.Name => morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Ta]]] => morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[Tb]]]))(_def.types),
      morphir.sdk.Dict.map(({
        case _ => 
          ((valueDef: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]]) =>
            (morphir.ir.AccessControlled.AccessControlled(
              valueDef.access,
              morphir.ir.Documented.map(morphir.ir.Value.mapDefinitionAttributes(tf)(vf))(valueDef.value)
            ) : morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Tb, Vb]]]))
      } : morphir.ir.Name.Name => morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Ta, Va]]] => morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Value.Definition[Tb, Vb]]]))(_def.values),
      _def.doc
    ) : morphir.ir.Module.Definition[Tb, Vb])
  
  def mapSpecificationAttributes[Ta, Tb](
    tf: Ta => Tb
  )(
    spec: morphir.ir.Module.Specification[Ta]
  ): morphir.ir.Module.Specification[Tb] =
    (morphir.ir.Module.Specification(
      morphir.sdk.Dict.map(({
        case _ => 
          ((typeSpec: morphir.ir.Documented.Documented[morphir.ir.Type.Specification[Ta]]) =>
            morphir.ir.Documented.map(morphir.ir.Type.mapSpecificationAttributes(tf))(typeSpec))
      } : morphir.ir.Name.Name => morphir.ir.Documented.Documented[morphir.ir.Type.Specification[Ta]] => morphir.ir.Documented.Documented[morphir.ir.Type.Specification[Tb]]))(spec.types),
      morphir.sdk.Dict.map(({
        case _ => 
          ((valueSpec: morphir.ir.Documented.Documented[morphir.ir.Value.Specification[Ta]]) =>
            morphir.ir.Documented.map(morphir.ir.Value.mapSpecificationAttributes(tf))(valueSpec))
      } : morphir.ir.Name.Name => morphir.ir.Documented.Documented[morphir.ir.Value.Specification[Ta]] => morphir.ir.Documented.Documented[morphir.ir.Value.Specification[Tb]]))(spec.values),
      spec.doc
    ) : morphir.ir.Module.Specification[Tb])

}