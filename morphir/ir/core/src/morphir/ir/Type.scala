package morphir.ir

/** Generated based on IR.Type
*/
object Type{

  type Constructor[A] = (morphir.ir.Name.Name, morphir.ir.Type.ConstructorArgs[A])
  
  type ConstructorArgs[A] = morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[A])]
  
  type Constructors[A] = morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Type.ConstructorArgs[A]]
  
  sealed trait Definition[A] {
  
    
  
  }
  
  object Definition{
  
    final case class CustomTypeDefinition[A](
      arg1: morphir.sdk.List.List[morphir.ir.Name.Name],
      arg2: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Type.Constructors[A]]
    ) extends morphir.ir.Type.Definition[A]{}
    
    final case class TypeAliasDefinition[A](
      arg1: morphir.sdk.List.List[morphir.ir.Name.Name],
      arg2: morphir.ir.Type.Type[A]
    ) extends morphir.ir.Type.Definition[A]{}
  
  }
  
  val CustomTypeDefinition: morphir.ir.Type.Definition.CustomTypeDefinition.type  = morphir.ir.Type.Definition.CustomTypeDefinition
  
  val TypeAliasDefinition: morphir.ir.Type.Definition.TypeAliasDefinition.type  = morphir.ir.Type.Definition.TypeAliasDefinition
  
  final case class DerivedTypeSpecificationDetails[A](
    baseType: morphir.ir.Type.Type[A],
    fromBaseType: morphir.ir.FQName.FQName,
    toBaseType: morphir.ir.FQName.FQName
  ){}
  
  final case class Field[A](
    name: morphir.ir.Name.Name,
    tpe: morphir.ir.Type.Type[A]
  ){}
  
  sealed trait Specification[A] {
  
    
  
  }
  
  object Specification{
  
    final case class CustomTypeSpecification[A](
      arg1: morphir.sdk.List.List[morphir.ir.Name.Name],
      arg2: morphir.ir.Type.Constructors[A]
    ) extends morphir.ir.Type.Specification[A]{}
    
    final case class DerivedTypeSpecification[A](
      arg1: morphir.sdk.List.List[morphir.ir.Name.Name],
      arg2: morphir.ir.Type.DerivedTypeSpecificationDetails[A]
    ) extends morphir.ir.Type.Specification[A]{}
    
    final case class OpaqueTypeSpecification[A](
      arg1: morphir.sdk.List.List[morphir.ir.Name.Name]
    ) extends morphir.ir.Type.Specification[A]{}
    
    final case class TypeAliasSpecification[A](
      arg1: morphir.sdk.List.List[morphir.ir.Name.Name],
      arg2: morphir.ir.Type.Type[A]
    ) extends morphir.ir.Type.Specification[A]{}
  
  }
  
  val CustomTypeSpecification: morphir.ir.Type.Specification.CustomTypeSpecification.type  = morphir.ir.Type.Specification.CustomTypeSpecification
  
  val DerivedTypeSpecification: morphir.ir.Type.Specification.DerivedTypeSpecification.type  = morphir.ir.Type.Specification.DerivedTypeSpecification
  
  val OpaqueTypeSpecification: morphir.ir.Type.Specification.OpaqueTypeSpecification.type  = morphir.ir.Type.Specification.OpaqueTypeSpecification
  
  val TypeAliasSpecification: morphir.ir.Type.Specification.TypeAliasSpecification.type  = morphir.ir.Type.Specification.TypeAliasSpecification
  
  sealed trait Type[A] {
  
    
  
  }
  
  object Type{
  
    final case class ExtensibleRecord[A](
      arg1: A,
      arg2: morphir.ir.Name.Name,
      arg3: morphir.sdk.List.List[morphir.ir.Type.Field[A]]
    ) extends morphir.ir.Type.Type[A]{}
    
    final case class Function[A](
      arg1: A,
      arg2: morphir.ir.Type.Type[A],
      arg3: morphir.ir.Type.Type[A]
    ) extends morphir.ir.Type.Type[A]{}
    
    final case class Record[A](
      arg1: A,
      arg2: morphir.sdk.List.List[morphir.ir.Type.Field[A]]
    ) extends morphir.ir.Type.Type[A]{}
    
    final case class Reference[A](
      arg1: A,
      arg2: morphir.ir.FQName.FQName,
      arg3: morphir.sdk.List.List[morphir.ir.Type.Type[A]]
    ) extends morphir.ir.Type.Type[A]{}
    
    final case class Tuple[A](
      arg1: A,
      arg2: morphir.sdk.List.List[morphir.ir.Type.Type[A]]
    ) extends morphir.ir.Type.Type[A]{}
    
    final case class Unit[A](
      arg1: A
    ) extends morphir.ir.Type.Type[A]{}
    
    final case class Variable[A](
      arg1: A,
      arg2: morphir.ir.Name.Name
    ) extends morphir.ir.Type.Type[A]{}
  
  }
  
  val ExtensibleRecord: morphir.ir.Type.Type.ExtensibleRecord.type  = morphir.ir.Type.Type.ExtensibleRecord
  
  val Function: morphir.ir.Type.Type.Function.type  = morphir.ir.Type.Type.Function
  
  val Record: morphir.ir.Type.Type.Record.type  = morphir.ir.Type.Type.Record
  
  val Reference: morphir.ir.Type.Type.Reference.type  = morphir.ir.Type.Type.Reference
  
  val Tuple: morphir.ir.Type.Type.Tuple.type  = morphir.ir.Type.Type.Tuple
  
  val Unit: morphir.ir.Type.Type.Unit.type  = morphir.ir.Type.Type.Unit
  
  val Variable: morphir.ir.Type.Type.Variable.type  = morphir.ir.Type.Type.Variable
  
  def collectReferences[Ta](
    tpe: morphir.ir.Type.Type[Ta]
  ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] = {
    def collectUnion(
      values: morphir.sdk.List.List[morphir.ir.Type.Type[Ta]]
    ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] =
      morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.ir.Type.collectReferences[Ta])(values))
    
    tpe match {
      case morphir.ir.Type.Variable(_, _) => 
        morphir.sdk.Set.empty
      case morphir.ir.Type.Reference(_, fQName, args) => 
        morphir.sdk.Set.insert(fQName)(collectUnion(args))
      case morphir.ir.Type.Tuple(_, elements) => 
        collectUnion(elements)
      case morphir.ir.Type.Record(_, fields) => 
        collectUnion(morphir.sdk.List.map(((x: morphir.ir.Type.Field[Ta]) =>
          x.tpe))(fields))
      case morphir.ir.Type.ExtensibleRecord(_, _, fields) => 
        collectUnion(morphir.sdk.List.map(((x: morphir.ir.Type.Field[Ta]) =>
          x.tpe))(fields))
      case morphir.ir.Type.Function(_, argType, returnType) => 
        collectUnion(morphir.sdk.List(
          argType,
          returnType
        ))
      case morphir.ir.Type.Unit(_) => 
        morphir.sdk.Set.empty
    }
  }
  
  def collectReferencesFromDefintion[Ta](
    typeDef: morphir.ir.Type.Definition[Ta]
  ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] =
    typeDef match {
      case morphir.ir.Type.TypeAliasDefinition(_, tpe) => 
        morphir.ir.Type.collectReferences(tpe)
      case morphir.ir.Type.CustomTypeDefinition(_, accessControlledType) => 
        morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.sdk.Basics.composeRight(morphir.sdk.Tuple.second[Name.Name, Type[Ta]])(morphir.ir.Type.collectReferences[Ta]))(morphir.sdk.List.concat(morphir.sdk.Dict.values(accessControlledType.value))))
    }
  
  def collectVariables[Ta](
    tpe: morphir.ir.Type.Type[Ta]
  ): morphir.sdk.Set.Set[morphir.ir.Name.Name] = {
    def collectUnion(
      values: morphir.sdk.List.List[morphir.ir.Type.Type[Ta]]
    ): morphir.sdk.Set.Set[morphir.ir.Name.Name] =
      morphir.sdk.List.foldl(morphir.sdk.Set.union[Name.Name])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.ir.Type.collectVariables[Ta])(values))
    
    tpe match {
      case morphir.ir.Type.Variable(_, name) => 
        morphir.sdk.Set.singleton(name)
      case morphir.ir.Type.Reference(_, _, args) => 
        collectUnion(args)
      case morphir.ir.Type.Tuple(_, elements) => 
        collectUnion(elements)
      case morphir.ir.Type.Record(_, fields) => 
        collectUnion(morphir.sdk.List.map(((x: morphir.ir.Type.Field[Ta]) =>
          x.tpe))(fields))
      case morphir.ir.Type.ExtensibleRecord(_, subjectName, fields) => 
        morphir.sdk.Set.insert(subjectName)(collectUnion(morphir.sdk.List.map(((x: morphir.ir.Type.Field[Ta]) =>
          x.tpe))(fields)))
      case morphir.ir.Type.Function(_, argType, returnType) => 
        collectUnion(morphir.sdk.List(
          argType,
          returnType
        ))
      case morphir.ir.Type.Unit(_) => 
        morphir.sdk.Set.empty
    }
  }
  
  def customTypeDefinition[A](
    typeParams: morphir.sdk.List.List[morphir.ir.Name.Name]
  )(
    ctors: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Type.Constructors[A]]
  ): morphir.ir.Type.Definition[A] =
    (morphir.ir.Type.CustomTypeDefinition(
      typeParams,
      ctors
    ) : morphir.ir.Type.Definition[A])
  
  def customTypeSpecification[A](
    typeParams: morphir.sdk.List.List[morphir.ir.Name.Name]
  )(
    ctors: morphir.ir.Type.Constructors[A]
  ): morphir.ir.Type.Specification[A] =
    (morphir.ir.Type.CustomTypeSpecification(
      typeParams,
      ctors
    ) : morphir.ir.Type.Specification[A])
  
  def definitionToSpecification[A](
    _def: morphir.ir.Type.Definition[A]
  ): morphir.ir.Type.Specification[A] =
    _def match {
      case morphir.ir.Type.TypeAliasDefinition(params, exp) => 
        (morphir.ir.Type.TypeAliasSpecification(
          params,
          exp
        ) : morphir.ir.Type.Specification[A])
      case morphir.ir.Type.CustomTypeDefinition(params, accessControlledCtors) => 
        morphir.ir.AccessControlled.withPublicAccess(accessControlledCtors) match {
          case morphir.sdk.Maybe.Just(ctors) => 
            (morphir.ir.Type.CustomTypeSpecification(
              params,
              ctors
            ) : morphir.ir.Type.Specification[A])
          case morphir.sdk.Maybe.Nothing => 
            (morphir.ir.Type.OpaqueTypeSpecification(params) : morphir.ir.Type.Specification[A])
        }
    }
  
  def definitionToSpecificationWithPrivate[A](
    _def: morphir.ir.Type.Definition[A]
  ): morphir.ir.Type.Specification[A] =
    _def match {
      case morphir.ir.Type.TypeAliasDefinition(params, exp) => 
        (morphir.ir.Type.TypeAliasSpecification(
          params,
          exp
        ) : morphir.ir.Type.Specification[A])
      case morphir.ir.Type.CustomTypeDefinition(params, accessControlledCtors) => 
        (morphir.ir.Type.CustomTypeSpecification(
          params,
          morphir.ir.AccessControlled.withPrivateAccess(accessControlledCtors)
        ) : morphir.ir.Type.Specification[A])
    }
  
  def eraseAttributes[A](
    typeDef: morphir.ir.Type.Definition[A]
  ): morphir.ir.Type.Definition[scala.Unit] =
    typeDef match {
      case morphir.ir.Type.TypeAliasDefinition(typeVars, tpe) => 
        (morphir.ir.Type.TypeAliasDefinition(
          typeVars,
          morphir.ir.Type.mapTypeAttributes(({
            case _ => 
              {}
          } : A => scala.Unit))(tpe)
        ) : morphir.ir.Type.Definition[scala.Unit])
      case morphir.ir.Type.CustomTypeDefinition(typeVars, acsCtrlConstructors) => 
        {
          def eraseCtor(
            types: morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[A])]
          ): morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[scala.Unit])] =
            morphir.sdk.List.map(({
              case (n, t) => 
                (n, morphir.ir.Type.mapTypeAttributes(({
                  case _ => 
                    {}
                } : A => scala.Unit))(t))
            } : ((morphir.ir.Name.Name, morphir.ir.Type.Type[A])) => (morphir.ir.Name.Name, morphir.ir.Type.Type[scala.Unit])))(types)
          
          def eraseAccessControlledCtors(
            acsCtrlCtors: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Type.Constructors[A]]
          ): morphir.ir.AccessControlled.AccessControlled[morphir.ir.Type.Constructors[scala.Unit]] =
            morphir.ir.AccessControlled.map(((ctors: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Type.ConstructorArgs[A]]) =>
              morphir.sdk.Dict.map(({
                case _ => 
                  eraseCtor
              } : morphir.ir.Name.Name => morphir.ir.Type.ConstructorArgs[A] => morphir.ir.Type.ConstructorArgs[scala.Unit]))(ctors)))(acsCtrlCtors)
          
          (morphir.ir.Type.CustomTypeDefinition(
            typeVars,
            eraseAccessControlledCtors(acsCtrlConstructors)
          ) : morphir.ir.Type.Definition[scala.Unit])
        }
    }
  
  def extensibleRecord[A](
    attributes: A
  )(
    variableName: morphir.ir.Name.Name
  )(
    fieldTypes: morphir.sdk.List.List[morphir.ir.Type.Field[A]]
  ): morphir.ir.Type.Type[A] =
    (morphir.ir.Type.ExtensibleRecord(
      attributes,
      variableName,
      fieldTypes
    ) : morphir.ir.Type.Type[A])
  
  def function[A](
    attributes: A
  )(
    argumentType: morphir.ir.Type.Type[A]
  )(
    returnType: morphir.ir.Type.Type[A]
  ): morphir.ir.Type.Type[A] =
    (morphir.ir.Type.Function(
      attributes,
      argumentType,
      returnType
    ) : morphir.ir.Type.Type[A])
  
  def mapDefinition[A, B, E](
    f: morphir.ir.Type.Type[A] => morphir.sdk.Result.Result[E, morphir.ir.Type.Type[B]]
  )(
    _def: morphir.ir.Type.Definition[A]
  ): morphir.sdk.Result.Result[morphir.sdk.List.List[E], morphir.ir.Type.Definition[B]] =
    _def match {
      case morphir.ir.Type.TypeAliasDefinition(params, tpe) => 
        morphir.sdk.Result.mapError(morphir.sdk.List.singleton[E])(morphir.sdk.Result.map(((a0: morphir.ir.Type.Type[B]) =>
          (morphir.ir.Type.TypeAliasDefinition(
            params,
            a0
          ) : morphir.ir.Type.Definition[B])))(f(tpe)))
      case morphir.ir.Type.CustomTypeDefinition(params, constructors) => 
        {
          val ctorsResult: morphir.sdk.Result.Result[morphir.sdk.List.List[E], morphir.ir.AccessControlled.AccessControlled[morphir.ir.Type.Constructors[B]]] = morphir.sdk.Result.mapError(morphir.sdk.List.concat[E])(morphir.sdk.Result.map(morphir.sdk.Basics.composeRight(morphir.sdk.Dict.fromList[morphir.ir.Name.Name, morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[B])]])(((a0: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[B])]]) =>
            (morphir.ir.AccessControlled.AccessControlled(
              constructors.access,
              a0
            ) : morphir.ir.AccessControlled.AccessControlled[morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[B])]]]))))(morphir.sdk.ResultList.keepAllErrors(morphir.sdk.List.map(({
            case (ctorName, ctorArgs) => 
              morphir.sdk.Result.map(morphir.sdk.Tuple.pair[Name.Name, ConstructorArgs[B]](ctorName))(morphir.sdk.ResultList.keepAllErrors(morphir.sdk.List.map(({
                case (argName, argType) => 
                  morphir.sdk.Result.map[E, Type[B], (Name.Name, Type[B])](morphir.sdk.Tuple.pair(argName))(f(argType))
              } : ((morphir.ir.Name.Name, morphir.ir.Type.Type[A])) => morphir.sdk.Result.Result[E, (morphir.ir.Name.Name, morphir.ir.Type.Type[B])]))(ctorArgs)))
          } : ((morphir.ir.Name.Name, morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[A])])) => morphir.sdk.Result.Result[morphir.sdk.List.List[E], (morphir.ir.Name.Name, morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[B])])]))(morphir.sdk.Dict.toList(constructors.value)))))
          
          morphir.sdk.Result.map(((a0: morphir.ir.AccessControlled.AccessControlled[morphir.ir.Type.Constructors[B]]) =>
            (morphir.ir.Type.CustomTypeDefinition(
              params,
              a0
            ) : morphir.ir.Type.Definition[B])))(ctorsResult)
        }
    }
  
  def mapDefinitionAttributes[A, B](
    f: A => B
  )(
    _def: morphir.ir.Type.Definition[A]
  ): morphir.ir.Type.Definition[B] =
    _def match {
      case morphir.ir.Type.TypeAliasDefinition(params, tpe) => 
        (morphir.ir.Type.TypeAliasDefinition(
          params,
          morphir.ir.Type.mapTypeAttributes(f)(tpe)
        ) : morphir.ir.Type.Definition[B])
      case morphir.ir.Type.CustomTypeDefinition(params, constructors) => 
        (morphir.ir.Type.CustomTypeDefinition(
          params,
          (morphir.ir.AccessControlled.AccessControlled(
            constructors.access,
            morphir.sdk.Dict.map(({
              case _ => 
                ((ctorArgs: morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[A])]) =>
                  morphir.sdk.List.map(({
                    case (argName, argType) => 
                      (argName, morphir.ir.Type.mapTypeAttributes(f)(argType))
                  } : ((morphir.ir.Name.Name, morphir.ir.Type.Type[A])) => (morphir.ir.Name.Name, morphir.ir.Type.Type[B])))(ctorArgs))
            } : morphir.ir.Name.Name => morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[A])] => morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[B])]))(constructors.value)
          ) : morphir.ir.AccessControlled.AccessControlled[morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[B])]]])
        ) : morphir.ir.Type.Definition[B])
    }
  
  def mapFieldName[A](
    f: morphir.ir.Name.Name => morphir.ir.Name.Name
  )(
    field: morphir.ir.Type.Field[A]
  ): morphir.ir.Type.Field[A] =
    (morphir.ir.Type.Field(
      f(field.name),
      field.tpe
    ) : morphir.ir.Type.Field[A])
  
  def mapFieldType[A, B](
    f: morphir.ir.Type.Type[A] => morphir.ir.Type.Type[B]
  )(
    field: morphir.ir.Type.Field[A]
  ): morphir.ir.Type.Field[B] =
    (morphir.ir.Type.Field(
      field.name,
      f(field.tpe)
    ) : morphir.ir.Type.Field[B])
  
  def mapSpecificationAttributes[A, B](
    f: A => B
  )(
    spec: morphir.ir.Type.Specification[A]
  ): morphir.ir.Type.Specification[B] =
    spec match {
      case morphir.ir.Type.TypeAliasSpecification(params, tpe) => 
        (morphir.ir.Type.TypeAliasSpecification(
          params,
          morphir.ir.Type.mapTypeAttributes(f)(tpe)
        ) : morphir.ir.Type.Specification[B])
      case morphir.ir.Type.OpaqueTypeSpecification(params) => 
        (morphir.ir.Type.OpaqueTypeSpecification(params) : morphir.ir.Type.Specification[B])
      case morphir.ir.Type.CustomTypeSpecification(params, constructors) => 
        (morphir.ir.Type.CustomTypeSpecification(
          params,
          morphir.sdk.Dict.map(({
            case _ => 
              ((ctorArgs: morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[A])]) =>
                morphir.sdk.List.map(({
                  case (argName, argType) => 
                    (argName, morphir.ir.Type.mapTypeAttributes(f)(argType))
                } : ((morphir.ir.Name.Name, morphir.ir.Type.Type[A])) => (morphir.ir.Name.Name, morphir.ir.Type.Type[B])))(ctorArgs))
          } : morphir.ir.Name.Name => morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[A])] => morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[B])]))(constructors)
        ) : morphir.ir.Type.Specification[B])
      case morphir.ir.Type.DerivedTypeSpecification(params, config) => 
        (morphir.ir.Type.DerivedTypeSpecification(
          params,
          morphir.ir.Type.DerivedTypeSpecificationDetails(
            baseType = morphir.ir.Type.mapTypeAttributes(f)(config.baseType),
            fromBaseType = config.fromBaseType,
            toBaseType = config.toBaseType
          )
        ) : morphir.ir.Type.Specification[B])
    }
  
  def mapTypeAttributes[A, B](
    f: A => B
  )(
    tpe: morphir.ir.Type.Type[A]
  ): morphir.ir.Type.Type[B] =
    tpe match {
      case morphir.ir.Type.Variable(a, name) => 
        (morphir.ir.Type.Variable(
          f(a),
          name
        ) : morphir.ir.Type.Type[B])
      case morphir.ir.Type.Reference(a, fQName, argTypes) => 
        (morphir.ir.Type.Reference(
          f(a),
          fQName,
          morphir.sdk.List.map(morphir.ir.Type.mapTypeAttributes(f))(argTypes)
        ) : morphir.ir.Type.Type[B])
      case morphir.ir.Type.Tuple(a, elemTypes) => 
        (morphir.ir.Type.Tuple(
          f(a),
          morphir.sdk.List.map(morphir.ir.Type.mapTypeAttributes(f))(elemTypes)
        ) : morphir.ir.Type.Type[B])
      case morphir.ir.Type.Record(a, fields) => 
        (morphir.ir.Type.Record(
          f(a),
          morphir.sdk.List.map(morphir.ir.Type.mapFieldType(morphir.ir.Type.mapTypeAttributes(f)))(fields)
        ) : morphir.ir.Type.Type[B])
      case morphir.ir.Type.ExtensibleRecord(a, name, fields) => 
        (morphir.ir.Type.ExtensibleRecord(
          f(a),
          name,
          morphir.sdk.List.map(morphir.ir.Type.mapFieldType(morphir.ir.Type.mapTypeAttributes(f)))(fields)
        ) : morphir.ir.Type.Type[B])
      case morphir.ir.Type.Function(a, argType, returnType) => 
        (morphir.ir.Type.Function(
          f(a),
          morphir.ir.Type.mapTypeAttributes(f)(argType),
          morphir.ir.Type.mapTypeAttributes(f)(returnType)
        ) : morphir.ir.Type.Type[B])
      case morphir.ir.Type.Unit(a) => 
        (morphir.ir.Type.Unit(f(a)) : morphir.ir.Type.Type[B])
    }
  
  def opaqueTypeSpecification[A](
    typeParams: morphir.sdk.List.List[morphir.ir.Name.Name]
  ): morphir.ir.Type.Specification[A] =
    (morphir.ir.Type.OpaqueTypeSpecification(typeParams) : morphir.ir.Type.Specification[A])
  
  def record[A](
    attributes: A
  )(
    fieldTypes: morphir.sdk.List.List[morphir.ir.Type.Field[A]]
  ): morphir.ir.Type.Type[A] =
    (morphir.ir.Type.Record(
      attributes,
      fieldTypes
    ) : morphir.ir.Type.Type[A])
  
  def reference[A](
    attributes: A
  )(
    typeName: morphir.ir.FQName.FQName
  )(
    typeParameters: morphir.sdk.List.List[morphir.ir.Type.Type[A]]
  ): morphir.ir.Type.Type[A] =
    (morphir.ir.Type.Reference(
      attributes,
      typeName,
      typeParameters
    ) : morphir.ir.Type.Type[A])
  
  def substituteTypeVariables[Ta](
    mapping: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Type.Type[Ta]]
  )(
    original: morphir.ir.Type.Type[Ta]
  ): morphir.ir.Type.Type[Ta] =
    original match {
      case morphir.ir.Type.Variable(_, varName) =>
        morphir.sdk.Maybe.withDefault(original)(morphir.sdk.Dict.get(varName)(mapping))
      case morphir.ir.Type.Reference(a, fQName, typeArgs) => 
        (morphir.ir.Type.Reference(
          a,
          fQName,
          morphir.sdk.List.map(morphir.ir.Type.substituteTypeVariables(mapping))(typeArgs)
        ) : morphir.ir.Type.Type[Ta])
      case morphir.ir.Type.Tuple(a, elemTypes) => 
        (morphir.ir.Type.Tuple(
          a,
          morphir.sdk.List.map(morphir.ir.Type.substituteTypeVariables(mapping))(elemTypes)
        ) : morphir.ir.Type.Type[Ta])
      case morphir.ir.Type.Record(a, fields) => 
        (morphir.ir.Type.Record(
          a,
          morphir.sdk.List.map(((field: morphir.ir.Type.Field[Ta]) =>
            (morphir.ir.Type.Field(
              field.name,
              morphir.ir.Type.substituteTypeVariables(mapping)(field.tpe)
            ) : morphir.ir.Type.Field[Ta])))(fields)
        ) : morphir.ir.Type.Type[Ta])
      case morphir.ir.Type.ExtensibleRecord(a, name, fields) => 
        (morphir.ir.Type.ExtensibleRecord(
          a,
          name,
          morphir.sdk.List.map(((field: morphir.ir.Type.Field[Ta]) =>
            (morphir.ir.Type.Field(
              field.name,
              morphir.ir.Type.substituteTypeVariables(mapping)(field.tpe)
            ) : morphir.ir.Type.Field[Ta])))(fields)
        ) : morphir.ir.Type.Type[Ta])
      case morphir.ir.Type.Function(a, argType, returnType) => 
        (morphir.ir.Type.Function(
          a,
          morphir.ir.Type.substituteTypeVariables(mapping)(argType),
          morphir.ir.Type.substituteTypeVariables(mapping)(returnType)
        ) : morphir.ir.Type.Type[Ta])
      case morphir.ir.Type.Unit(a) => 
        (morphir.ir.Type.Unit(a) : morphir.ir.Type.Type[Ta])
    }
  
  def _toString[A](
    tpe: morphir.ir.Type.Type[A]
  ): morphir.sdk.String.String =
    tpe match {
      case morphir.ir.Type.Variable(_, name) => 
        morphir.ir.Name.toCamelCase(name)
      case morphir.ir.Type.Reference(_, (packageName, moduleName, localName), args) => 
        {
          val referenceName: morphir.sdk.String.String = morphir.sdk.String.join(""".""")(morphir.sdk.List(
            morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(packageName),
            morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(moduleName),
            morphir.ir.Name.toTitleCase(localName)
          ))
          
          morphir.sdk.String.join(""" """)(morphir.sdk.List.cons(referenceName)(morphir.sdk.List.map(morphir.ir.Type._toString[A])(args)))
        }
      case morphir.ir.Type.Tuple(_, elems) => 
        morphir.sdk.String.concat(morphir.sdk.List(
          """( """,
          morphir.sdk.String.join(""", """)(morphir.sdk.List.map(morphir.ir.Type._toString[A])(elems)),
          """ )"""
        ))
      case morphir.ir.Type.Record(_, fields) => 
        morphir.sdk.String.concat(morphir.sdk.List(
          """{ """,
          morphir.sdk.String.join(""", """)(morphir.sdk.List.map(((field: morphir.ir.Type.Field[A]) =>
            morphir.sdk.String.concat(morphir.sdk.List(
              morphir.ir.Name.toCamelCase(field.name),
              """ : """,
              morphir.ir.Type._toString(field.tpe)
            ))))(fields)),
          """ }"""
        ))
      case morphir.ir.Type.ExtensibleRecord(_, varName, fields) => 
        morphir.sdk.String.concat(morphir.sdk.List(
          """{ """,
          morphir.ir.Name.toCamelCase(varName),
          """ | """,
          morphir.sdk.String.join(""", """)(morphir.sdk.List.map(((field: morphir.ir.Type.Field[A]) =>
            morphir.sdk.String.concat(morphir.sdk.List(
              morphir.ir.Name.toCamelCase(field.name),
              """ : """,
              morphir.ir.Type._toString(field.tpe)
            ))))(fields)),
          """ }"""
        ))
      case morphir.ir.Type.Function(_, argType @ morphir.ir.Type.Function(_, _, _), returnType) => 
        morphir.sdk.String.concat(morphir.sdk.List(
          """(""",
          morphir.ir.Type._toString(argType),
          """) -> """,
          morphir.ir.Type._toString(returnType)
        ))
      case morphir.ir.Type.Function(_, argType, returnType) => 
        morphir.sdk.String.concat(morphir.sdk.List(
          morphir.ir.Type._toString(argType),
          """ -> """,
          morphir.ir.Type._toString(returnType)
        ))
      case morphir.ir.Type.Unit(_) => 
        """()"""
    }
  
  def tuple[A](
    attributes: A
  )(
    elementTypes: morphir.sdk.List.List[morphir.ir.Type.Type[A]]
  ): morphir.ir.Type.Type[A] =
    (morphir.ir.Type.Tuple(
      attributes,
      elementTypes
    ) : morphir.ir.Type.Type[A])
  
  def typeAliasDefinition[A](
    typeParams: morphir.sdk.List.List[morphir.ir.Name.Name]
  )(
    typeExp: morphir.ir.Type.Type[A]
  ): morphir.ir.Type.Definition[A] =
    (morphir.ir.Type.TypeAliasDefinition(
      typeParams,
      typeExp
    ) : morphir.ir.Type.Definition[A])
  
  def typeAliasSpecification[A](
    typeParams: morphir.sdk.List.List[morphir.ir.Name.Name]
  )(
    typeExp: morphir.ir.Type.Type[A]
  ): morphir.ir.Type.Specification[A] =
    (morphir.ir.Type.TypeAliasSpecification(
      typeParams,
      typeExp
    ) : morphir.ir.Type.Specification[A])
  
  def typeAttributes[A](
    tpe: morphir.ir.Type.Type[A]
  ): A =
    tpe match {
      case morphir.ir.Type.Variable(a, _) => 
        a
      case morphir.ir.Type.Reference(a, _, _) => 
        a
      case morphir.ir.Type.Tuple(a, _) => 
        a
      case morphir.ir.Type.Record(a, _) => 
        a
      case morphir.ir.Type.ExtensibleRecord(a, _, _) => 
        a
      case morphir.ir.Type.Function(a, _, _) => 
        a
      case morphir.ir.Type.Unit(a) => 
        a
    }
  
  def unit[A](
    attributes: A
  ): morphir.ir.Type.Type[A] =
    (morphir.ir.Type.Unit(attributes) : morphir.ir.Type.Type[A])
  
  def variable[A](
    attributes: A
  )(
    name: morphir.ir.Name.Name
  ): morphir.ir.Type.Type[A] =
    (morphir.ir.Type.Variable(
      attributes,
      name
    ) : morphir.ir.Type.Type[A])

}