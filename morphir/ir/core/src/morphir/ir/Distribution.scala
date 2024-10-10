package morphir.ir

/** Generated based on IR.Distribution
*/
object Distribution{

  sealed trait Distribution {
  
    
  
  }
  
  object Distribution{
  
    final case class Library(
      arg1: morphir.ir.Package.PackageName,
      arg2: morphir.sdk.Dict.Dict[morphir.ir.Package.PackageName, morphir.ir.Package.Specification[scala.Unit]],
      arg3: morphir.ir.Package.Definition[scala.Unit, morphir.ir.Type.Type[scala.Unit]]
    ) extends morphir.ir.Distribution.Distribution{}
  
  }
  
  val Library: morphir.ir.Distribution.Distribution.Library.type  = morphir.ir.Distribution.Distribution.Library
  
  def insertDependency(
    dependencyPackageName: morphir.ir.Package.PackageName
  )(
    dependencyPackageSpec: morphir.ir.Package.Specification[scala.Unit]
  )(
    distribution: morphir.ir.Distribution.Distribution
  ): morphir.ir.Distribution.Distribution =
    distribution match {
      case morphir.ir.Distribution.Library(packageName, dependencies, packageDef) => 
        (morphir.ir.Distribution.Library(
          packageName,
          morphir.sdk.Dict.insert(dependencyPackageName)(dependencyPackageSpec)(dependencies),
          packageDef
        ) : morphir.ir.Distribution.Distribution)
    }
  
  def lookupBaseTypeName: morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[morphir.ir.FQName.FQName] =
    ({
      case fQName @ (packageName, moduleName, localName) => 
        ((distribution: morphir.ir.Distribution.Distribution) =>
          morphir.sdk.Maybe.andThen(((typeSpec: morphir.ir.Type.Specification[scala.Unit]) =>
            typeSpec match {
              case morphir.ir.Type.TypeAliasSpecification(_, morphir.ir.Type.Reference(_, aliasFQName, _)) => 
                morphir.ir.Distribution.lookupBaseTypeName(aliasFQName)(distribution)
              case _ => 
                (morphir.sdk.Maybe.Just(fQName) : morphir.sdk.Maybe.Maybe[(morphir.ir.Path.Path, morphir.ir.Path.Path, morphir.ir.Name.Name)])
            }))(morphir.sdk.Maybe.andThen[Module.Specification[Unit], Type.Specification[Unit]](morphir.ir.Module.lookupTypeSpecification(localName))(morphir.ir.Distribution.lookupModuleSpecification(packageName)(moduleName)(distribution))))
    } : morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[morphir.ir.FQName.FQName])
  
  def lookupModuleSpecification(
    packageName: morphir.ir.Package.PackageName
  )(
    modulePath: morphir.ir.Module.ModuleName
  )(
    distribution: morphir.ir.Distribution.Distribution
  ): morphir.sdk.Maybe.Maybe[morphir.ir.Module.Specification[scala.Unit]] =
    distribution match {
      case morphir.ir.Distribution.Library(libraryPackageName, dependencies, packageDef) => 
        if (morphir.sdk.Basics.equal(packageName)(libraryPackageName)) {
          morphir.ir.Package.lookupModuleSpecification(modulePath)(morphir.ir.Package.definitionToSpecificationWithPrivate(packageDef))
        } else {
          morphir.sdk.Maybe.andThen[Package.Specification[Unit], Module.Specification[Unit]](morphir.ir.Package.lookupModuleSpecification(modulePath))(morphir.sdk.Dict.get(packageName)(dependencies))
        }
    }
  
  def lookupPackageName(
    distribution: morphir.ir.Distribution.Distribution
  ): morphir.ir.Package.PackageName =
    distribution match {
      case morphir.ir.Distribution.Library(packageName, _, _) => 
        packageName
    }
  
  def lookupPackageSpecification(
    distribution: morphir.ir.Distribution.Distribution
  ): morphir.ir.Package.Specification[scala.Unit] =
    distribution match {
      case morphir.ir.Distribution.Library(_, _, packageDef) => 
        morphir.ir.Package.mapSpecificationAttributes(({
          case _ => 
            {}
        } : scala.Unit => scala.Unit))(morphir.ir.Package.definitionToSpecificationWithPrivate(packageDef))
    }
  
  def lookupTypeConstructor: morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[(morphir.ir.FQName.FQName, morphir.sdk.List.List[morphir.ir.Name.Name], morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[scala.Unit])])] =
    ({
      case (packageName, moduleName, ctorName) => 
        ((distro: morphir.ir.Distribution.Distribution) =>
          morphir.sdk.Maybe.andThen(((moduleSpec: morphir.ir.Module.Specification[scala.Unit]) =>
            morphir.sdk.List.head(morphir.sdk.List.filterMap(({
              case (typeName, documentedTypeSpec) => 
                documentedTypeSpec.value match {
                  case morphir.ir.Type.CustomTypeSpecification(typeArgs, constructors) => 
                    morphir.sdk.Maybe.map(((constructorArgs: morphir.ir.Type.ConstructorArgs[scala.Unit]) =>
                      ((packageName, moduleName, typeName), typeArgs, constructorArgs)))(morphir.sdk.Dict.get(ctorName)(constructors))
                  case _ => 
                    (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[((morphir.ir.Path.Path, morphir.ir.Path.Path, morphir.ir.Name.Name), morphir.sdk.List.List[morphir.ir.Name.Name], morphir.ir.Type.ConstructorArgs[scala.Unit])])
                }
            } : ((morphir.ir.Name.Name, morphir.ir.Documented.Documented[morphir.ir.Type.Specification[scala.Unit]])) => morphir.sdk.Maybe.Maybe[((morphir.ir.Path.Path, morphir.ir.Path.Path, morphir.ir.Name.Name), morphir.sdk.List.List[morphir.ir.Name.Name], morphir.ir.Type.ConstructorArgs[scala.Unit])]))(morphir.sdk.Dict.toList(moduleSpec.types)))))(morphir.ir.Distribution.lookupModuleSpecification(packageName)(moduleName)(distro)))
    } : morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[(morphir.ir.FQName.FQName, morphir.sdk.List.List[morphir.ir.Name.Name], morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[scala.Unit])])])
  
  def lookupTypeSpecification: morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[morphir.ir.Type.Specification[scala.Unit]] =
    ({
      case (packageName, moduleName, localName) => 
        ((distribution: morphir.ir.Distribution.Distribution) =>
          morphir.sdk.Maybe.andThen[Module.Specification[Unit], Type.Specification[Unit]](morphir.ir.Module.lookupTypeSpecification(localName))(morphir.ir.Distribution.lookupModuleSpecification(packageName)(moduleName)(distribution)))
    } : morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[morphir.ir.Type.Specification[scala.Unit]])
  
  def lookupValueDefinition: morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[morphir.ir.Value.Definition[scala.Unit, morphir.ir.Type.Type[scala.Unit]]] =
    ({
      case (packageName, moduleName, localName) => 
        ((distribution: morphir.ir.Distribution.Distribution) =>
          distribution match {
            case morphir.ir.Distribution.Library(pName, _, packageDef) => 
              if (morphir.sdk.Basics.equal(pName)(packageName)) {
                morphir.sdk.Maybe.andThen[Module.Definition[Unit, Type.Type[Unit]], Value.Definition[Unit, Type.Type[Unit]]](morphir.ir.Module.lookupValueDefinition(localName))(morphir.ir.Package.lookupModuleDefinition(moduleName)(packageDef))
              } else {
                (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Definition[scala.Unit, morphir.ir.Type.Type[scala.Unit]]])
              }
          })
    } : morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[morphir.ir.Value.Definition[scala.Unit, morphir.ir.Type.Type[scala.Unit]]])
  
  def lookupValueSpecification: morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[morphir.ir.Value.Specification[scala.Unit]] =
    ({
      case (packageName, moduleName, localName) => 
        ((distribution: morphir.ir.Distribution.Distribution) =>
          morphir.sdk.Maybe.andThen[Module.Specification[Unit], Value.Specification[Unit]](morphir.ir.Module.lookupValueSpecification(localName))(morphir.ir.Distribution.lookupModuleSpecification(packageName)(moduleName)(distribution)))
    } : morphir.ir.FQName.FQName => morphir.ir.Distribution.Distribution => morphir.sdk.Maybe.Maybe[morphir.ir.Value.Specification[scala.Unit]])
  
  def resolveAliases(
    fQName: morphir.ir.FQName.FQName
  )(
    distro: morphir.ir.Distribution.Distribution
  ): morphir.ir.FQName.FQName =
    morphir.sdk.Maybe.withDefault(fQName)(morphir.sdk.Maybe.map(((typeSpec: morphir.ir.Type.Specification[scala.Unit]) =>
      typeSpec match {
        case morphir.ir.Type.TypeAliasSpecification(_, morphir.ir.Type.Reference(_, aliasFQName, _)) => 
          aliasFQName
        case _ => 
          fQName
      }))(morphir.ir.Distribution.lookupTypeSpecification(fQName)(distro)))
  
  def resolveRecordConstructors[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  )(
    distro: morphir.ir.Distribution.Distribution
  ): morphir.ir.Value.Value[Ta, Va] =
    morphir.ir.Value.rewriteValue(((v: morphir.ir.Value.Value[Ta, Va]) =>
      v match {
        case morphir.ir.Value.Apply(_, fun, lastArg) => 
          {
            val (bottomFun, args) = morphir.ir.Value.uncurryApply(fun)(lastArg)
            
            bottomFun match {
              case morphir.ir.Value.Constructor(va, fqn) => 
                morphir.sdk.Maybe.andThen(((typeSpec: morphir.ir.Type.Specification[scala.Unit]) =>
                  typeSpec match {
                    case morphir.ir.Type.TypeAliasSpecification(_, morphir.ir.Type.Record(_, fields)) => 
                      (morphir.sdk.Maybe.Just((morphir.ir.Value.Record(
                        va,
                        morphir.sdk.Dict.fromList(morphir.sdk.List.map2[Name.Name, Value.Value[Ta, Va], (Name.Name, Value.Value[Ta, Va])](morphir.sdk.Tuple.pair)(morphir.sdk.List.map(((x: morphir.ir.Type.Field[scala.Unit]) =>
                          x.name))(fields))(args))
                      ) : morphir.ir.Value.Value[Ta, Va])) : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
                    case _ => 
                      (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
                  }))(morphir.ir.Distribution.lookupTypeSpecification(fqn)(distro))
              case _ => 
                (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
            }
          }
        case _ => 
          (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
      }))(value)
  
  def resolveType(
    tpe: morphir.ir.Type.Type[scala.Unit]
  )(
    distro: morphir.ir.Distribution.Distribution
  ): morphir.ir.Type.Type[scala.Unit] =
    tpe match {
      case morphir.ir.Type.Variable(a, name) => 
        (morphir.ir.Type.Variable(
          a,
          name
        ) : morphir.ir.Type.Type[scala.Unit])
      case morphir.ir.Type.Reference(_, fQName, typeParams) => 
        morphir.sdk.Maybe.withDefault(tpe)(morphir.sdk.Maybe.map(((typeSpec: morphir.ir.Type.Specification[scala.Unit]) =>
          typeSpec match {
            case morphir.ir.Type.TypeAliasSpecification(typeParamNames, targetType) => 
              morphir.ir.Type.substituteTypeVariables(morphir.sdk.Dict.fromList(morphir.sdk.List.map2[Name.Name, Type.Type[Unit], (Name.Name, Type.Type[Unit])](morphir.sdk.Tuple.pair)(typeParamNames)(typeParams)))(targetType)
            case _ => 
              tpe
          }))(morphir.ir.Distribution.lookupTypeSpecification(fQName)(distro)))
      case morphir.ir.Type.Tuple(a, elemTypes) => 
        (morphir.ir.Type.Tuple(
          a,
          morphir.sdk.List.map(((t: morphir.ir.Type.Type[scala.Unit]) =>
            morphir.ir.Distribution.resolveType(t)(distro)))(elemTypes)
        ) : morphir.ir.Type.Type[scala.Unit])
      case morphir.ir.Type.Record(a, fields) => 
        (morphir.ir.Type.Record(
          a,
          morphir.sdk.List.map(((f: morphir.ir.Type.Field[scala.Unit]) =>
            f.copy(tpe = morphir.ir.Distribution.resolveType(f.tpe)(distro))))(fields)
        ) : morphir.ir.Type.Type[scala.Unit])
      case morphir.ir.Type.ExtensibleRecord(a, varName, fields) => 
        (morphir.ir.Type.ExtensibleRecord(
          a,
          varName,
          morphir.sdk.List.map(((f: morphir.ir.Type.Field[scala.Unit]) =>
            f.copy(tpe = morphir.ir.Distribution.resolveType(f.tpe)(distro))))(fields)
        ) : morphir.ir.Type.Type[scala.Unit])
      case morphir.ir.Type.Function(a, argType, returnType) => 
        (morphir.ir.Type.Function(
          a,
          morphir.ir.Distribution.resolveType(argType)(distro),
          morphir.ir.Distribution.resolveType(returnType)(distro)
        ) : morphir.ir.Type.Type[scala.Unit])
      case morphir.ir.Type.Unit(a) => 
        (morphir.ir.Type.Unit(a) : morphir.ir.Type.Type[scala.Unit])
    }
  
  def typeSpecifications: morphir.ir.Distribution.Distribution => morphir.sdk.Dict.Dict[morphir.ir.FQName.FQName, morphir.ir.Type.Specification[scala.Unit]] =
    ({
      case morphir.ir.Distribution.Library(packageName, dependencies, packageDef) => 
        {
          val typeSpecsInDependencies: morphir.sdk.Dict.Dict[morphir.ir.FQName.FQName, morphir.ir.Type.Specification[scala.Unit]] = morphir.sdk.Dict.fromList(morphir.sdk.List.concatMap(({
            case (pName, pSpec) => 
              morphir.sdk.List.concatMap(({
                case (mName, mSpec) => 
                  morphir.sdk.List.map(({
                    case (tName, documentedTypeSpec) => 
                      ((pName, mName, tName), documentedTypeSpec.value)
                  } : ((morphir.ir.Name.Name, morphir.ir.Documented.Documented[morphir.ir.Type.Specification[scala.Unit]])) => ((morphir.ir.Path.Path, morphir.ir.Path.Path, morphir.ir.Name.Name), morphir.ir.Type.Specification[scala.Unit])))(morphir.sdk.Dict.toList(mSpec.types))
              } : ((morphir.ir.Path.Path, morphir.ir.Module.Specification[scala.Unit])) => morphir.sdk.List.List[((morphir.ir.Path.Path, morphir.ir.Path.Path, morphir.ir.Name.Name), morphir.ir.Type.Specification[scala.Unit])]))(morphir.sdk.Dict.toList(pSpec.modules))
          } : ((morphir.ir.Path.Path, morphir.ir.Package.Specification[scala.Unit])) => morphir.sdk.List.List[((morphir.ir.Path.Path, morphir.ir.Path.Path, morphir.ir.Name.Name), morphir.ir.Type.Specification[scala.Unit])]))(morphir.sdk.Dict.toList(dependencies)))
          
          val typeSpecsInPackage: morphir.sdk.Dict.Dict[morphir.ir.FQName.FQName, morphir.ir.Type.Specification[scala.Unit]] = morphir.sdk.Dict.fromList(morphir.sdk.List.concatMap(({
            case (mName, accessControlledModuleDef) => 
              morphir.sdk.List.map(({
                case (tName, accessControlledDocumentedTypeDef) => 
                  ((packageName, mName, tName), morphir.ir.Type.definitionToSpecification(accessControlledDocumentedTypeDef.value.value))
              } : ((morphir.ir.Name.Name, morphir.ir.AccessControlled.AccessControlled[morphir.ir.Documented.Documented[morphir.ir.Type.Definition[scala.Unit]]])) => ((morphir.ir.Path.Path, morphir.ir.Module.ModuleName, morphir.ir.Name.Name), morphir.ir.Type.Specification[scala.Unit])))(morphir.sdk.Dict.toList(accessControlledModuleDef.value.types))
          } : ((morphir.ir.Module.ModuleName, morphir.ir.AccessControlled.AccessControlled[morphir.ir.Module.Definition[scala.Unit, morphir.ir.Type.Type[scala.Unit]]])) => morphir.sdk.List.List[((morphir.ir.Path.Path, morphir.ir.Module.ModuleName, morphir.ir.Name.Name), morphir.ir.Type.Specification[scala.Unit])]))(morphir.sdk.Dict.toList(packageDef.modules)))
          
          morphir.sdk.Dict.union(typeSpecsInDependencies)(typeSpecsInPackage)
        }
    } : morphir.ir.Distribution.Distribution => morphir.sdk.Dict.Dict[morphir.ir.FQName.FQName, morphir.ir.Type.Specification[scala.Unit]])

}