package morphir.ir

/** Generated based on IR.Value
*/
object Value{

  implicit val nameOrdering: Ordering[Name.Name] =
      (_: Name.Name, _: Name.Name) => 0

  final case class Definition[Ta, Va](
    inputTypes: morphir.sdk.List.List[(morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])],
    outputType: morphir.ir.Type.Type[Ta],
    body: morphir.ir.Value.Value[Ta, Va]
  ){}

  sealed trait Pattern[A] {



  }

  object Pattern{

    final case class AsPattern[A](
      arg1: A,
      arg2: morphir.ir.Value.Pattern[A],
      arg3: morphir.ir.Name.Name
    ) extends morphir.ir.Value.Pattern[A]{}

    final case class ConstructorPattern[A](
      arg1: A,
      arg2: morphir.ir.FQName.FQName,
      arg3: morphir.sdk.List.List[morphir.ir.Value.Pattern[A]]
    ) extends morphir.ir.Value.Pattern[A]{}

    final case class EmptyListPattern[A](
      arg1: A
    ) extends morphir.ir.Value.Pattern[A]{}

    final case class HeadTailPattern[A](
      arg1: A,
      arg2: morphir.ir.Value.Pattern[A],
      arg3: morphir.ir.Value.Pattern[A]
    ) extends morphir.ir.Value.Pattern[A]{}

    final case class LiteralPattern[A](
      arg1: A,
      arg2: morphir.ir.Literal.Literal
    ) extends morphir.ir.Value.Pattern[A]{}

    final case class TuplePattern[A](
      arg1: A,
      arg2: morphir.sdk.List.List[morphir.ir.Value.Pattern[A]]
    ) extends morphir.ir.Value.Pattern[A]{}

    final case class UnitPattern[A](
      arg1: A
    ) extends morphir.ir.Value.Pattern[A]{}

    final case class WildcardPattern[A](
      arg1: A
    ) extends morphir.ir.Value.Pattern[A]{}

  }

  val AsPattern: morphir.ir.Value.Pattern.AsPattern.type  = morphir.ir.Value.Pattern.AsPattern

  val ConstructorPattern: morphir.ir.Value.Pattern.ConstructorPattern.type  = morphir.ir.Value.Pattern.ConstructorPattern

  val EmptyListPattern: morphir.ir.Value.Pattern.EmptyListPattern.type  = morphir.ir.Value.Pattern.EmptyListPattern

  val HeadTailPattern: morphir.ir.Value.Pattern.HeadTailPattern.type  = morphir.ir.Value.Pattern.HeadTailPattern

  val LiteralPattern: morphir.ir.Value.Pattern.LiteralPattern.type  = morphir.ir.Value.Pattern.LiteralPattern

  val TuplePattern: morphir.ir.Value.Pattern.TuplePattern.type  = morphir.ir.Value.Pattern.TuplePattern

  val UnitPattern: morphir.ir.Value.Pattern.UnitPattern.type  = morphir.ir.Value.Pattern.UnitPattern

  val WildcardPattern: morphir.ir.Value.Pattern.WildcardPattern.type  = morphir.ir.Value.Pattern.WildcardPattern

  type RawValue = morphir.ir.Value.Value[scala.Unit, scala.Unit]

  final case class Specification[Ta](
    inputs: morphir.sdk.List.List[(morphir.ir.Name.Name, morphir.ir.Type.Type[Ta])],
    output: morphir.ir.Type.Type[Ta]
  ){}

  type TypedValue = morphir.ir.Value.Value[scala.Unit, morphir.ir.Type.Type[scala.Unit]]

  sealed trait Value[Ta, Va] {



  }

  object Value{

    final case class Apply[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Value.Value[Ta, Va],
      arg3: morphir.ir.Value.Value[Ta, Va]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Constructor[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.FQName.FQName
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Destructure[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Value.Pattern[Va],
      arg3: morphir.ir.Value.Value[Ta, Va],
      arg4: morphir.ir.Value.Value[Ta, Va]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Field[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Value.Value[Ta, Va],
      arg3: morphir.ir.Name.Name
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class FieldFunction[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Name.Name
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class IfThenElse[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Value.Value[Ta, Va],
      arg3: morphir.ir.Value.Value[Ta, Va],
      arg4: morphir.ir.Value.Value[Ta, Va]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Lambda[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Value.Pattern[Va],
      arg3: morphir.ir.Value.Value[Ta, Va]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class LetDefinition[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Name.Name,
      arg3: morphir.ir.Value.Definition[Ta, Va],
      arg4: morphir.ir.Value.Value[Ta, Va]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class LetRecursion[Ta, Va](
      arg1: Va,
      arg2: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Value.Definition[Ta, Va]],
      arg3: morphir.ir.Value.Value[Ta, Va]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class List[Ta, Va](
      arg1: Va,
      arg2: morphir.sdk.List.List[morphir.ir.Value.Value[Ta, Va]]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Literal[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Literal.Literal
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class PatternMatch[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Value.Value[Ta, Va],
      arg3: morphir.sdk.List.List[(morphir.ir.Value.Pattern[Va], morphir.ir.Value.Value[Ta, Va])]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Record[Ta, Va](
      arg1: Va,
      arg2: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, Va]]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Reference[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.FQName.FQName
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Tuple[Ta, Va](
      arg1: Va,
      arg2: morphir.sdk.List.List[morphir.ir.Value.Value[Ta, Va]]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Unit[Ta, Va](
      arg1: Va
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class UpdateRecord[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Value.Value[Ta, Va],
      arg3: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, Va]]
    ) extends morphir.ir.Value.Value[Ta, Va]{}

    final case class Variable[Ta, Va](
      arg1: Va,
      arg2: morphir.ir.Name.Name
    ) extends morphir.ir.Value.Value[Ta, Va]{}

  }

  val Apply: morphir.ir.Value.Value.Apply.type  = morphir.ir.Value.Value.Apply

  val Constructor: morphir.ir.Value.Value.Constructor.type  = morphir.ir.Value.Value.Constructor

  val Destructure: morphir.ir.Value.Value.Destructure.type  = morphir.ir.Value.Value.Destructure

  val Field: morphir.ir.Value.Value.Field.type  = morphir.ir.Value.Value.Field

  val FieldFunction: morphir.ir.Value.Value.FieldFunction.type  = morphir.ir.Value.Value.FieldFunction

  val IfThenElse: morphir.ir.Value.Value.IfThenElse.type  = morphir.ir.Value.Value.IfThenElse

  val Lambda: morphir.ir.Value.Value.Lambda.type  = morphir.ir.Value.Value.Lambda

  val LetDefinition: morphir.ir.Value.Value.LetDefinition.type  = morphir.ir.Value.Value.LetDefinition

  val LetRecursion: morphir.ir.Value.Value.LetRecursion.type  = morphir.ir.Value.Value.LetRecursion

  val List: morphir.ir.Value.Value.List.type  = morphir.ir.Value.Value.List

  val Literal: morphir.ir.Value.Value.Literal.type  = morphir.ir.Value.Value.Literal

  val PatternMatch: morphir.ir.Value.Value.PatternMatch.type  = morphir.ir.Value.Value.PatternMatch

  val Record: morphir.ir.Value.Value.Record.type  = morphir.ir.Value.Value.Record

  val Reference: morphir.ir.Value.Value.Reference.type  = morphir.ir.Value.Value.Reference

  val Tuple: morphir.ir.Value.Value.Tuple.type  = morphir.ir.Value.Value.Tuple

  val Unit: morphir.ir.Value.Value.Unit.type  = morphir.ir.Value.Value.Unit

  val UpdateRecord: morphir.ir.Value.Value.UpdateRecord.type  = morphir.ir.Value.Value.UpdateRecord

  val Variable: morphir.ir.Value.Value.Variable.type  = morphir.ir.Value.Value.Variable

  def apply[Ta, Va](
    attributes: Va
  )(
    function: morphir.ir.Value.Value[Ta, Va]
  )(
    argument: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Apply(
      attributes,
      function,
      argument
    ) : morphir.ir.Value.Value[Ta, Va])

  def asPattern[A](
    attributes: A
  )(
    pattern: morphir.ir.Value.Pattern[A]
  )(
    name: morphir.ir.Name.Name
  ): morphir.ir.Value.Pattern[A] =
    (morphir.ir.Value.AsPattern(
      attributes,
      pattern,
      name
    ) : morphir.ir.Value.Pattern[A])

  def collectDefinitionAttributes[Ta, Va](
    d: morphir.ir.Value.Definition[Ta, Va]
  ): morphir.sdk.List.List[Va] =
    morphir.sdk.List.append(morphir.sdk.List.map(({
      case (_, attr, _) =>
        attr
    } : ((morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])) => Va))(d.inputTypes))(morphir.ir.Value.collectValueAttributes(d.body))

  def collectPatternAttributes[A](
    p: morphir.ir.Value.Pattern[A]
  ): morphir.sdk.List.List[A] =
    p match {
      case morphir.ir.Value.WildcardPattern(a) =>
        morphir.sdk.List(a)
      case morphir.ir.Value.AsPattern(a, p2, _) =>
        morphir.sdk.List.cons(a)(morphir.ir.Value.collectPatternAttributes(p2))
      case morphir.ir.Value.TuplePattern(a, elementPatterns) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concatMap(morphir.ir.Value.collectPatternAttributes[A])(elementPatterns))
      case morphir.ir.Value.ConstructorPattern(a, _, argumentPatterns) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concatMap(morphir.ir.Value.collectPatternAttributes[A])(argumentPatterns))
      case morphir.ir.Value.EmptyListPattern(a) =>
        morphir.sdk.List(a)
      case morphir.ir.Value.HeadTailPattern(a, headPattern, tailPattern) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concat(morphir.sdk.List(
          morphir.ir.Value.collectPatternAttributes(headPattern),
          morphir.ir.Value.collectPatternAttributes(tailPattern)
        )))
      case morphir.ir.Value.LiteralPattern(a, _) =>
        morphir.sdk.List(a)
      case morphir.ir.Value.UnitPattern(a) =>
        morphir.sdk.List(a)
    }

  def collectPatternReferences[Va](
    pattern: morphir.ir.Value.Pattern[Va]
  ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] =
    pattern match {
      case morphir.ir.Value.WildcardPattern(_) =>
        morphir.sdk.Set.empty
      case morphir.ir.Value.AsPattern(_, subject, _) =>
        morphir.ir.Value.collectPatternReferences(subject)
      case morphir.ir.Value.TuplePattern(_, elemPatterns) =>
        morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.ir.Value.collectPatternReferences[Va])(elemPatterns))
      case morphir.ir.Value.ConstructorPattern(_, fQName, argPatterns) =>
        morphir.sdk.Set.insert(fQName)(morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.ir.Value.collectPatternReferences[Va])(argPatterns)))
      case morphir.ir.Value.EmptyListPattern(_) =>
        morphir.sdk.Set.empty
      case morphir.ir.Value.HeadTailPattern(_, headPattern, tailPattern) =>
        morphir.sdk.Set.union(morphir.ir.Value.collectPatternReferences(headPattern))(morphir.ir.Value.collectPatternReferences(tailPattern))
      case morphir.ir.Value.LiteralPattern(_, _) =>
        morphir.sdk.Set.empty
      case morphir.ir.Value.UnitPattern(_) =>
        morphir.sdk.Set.empty
    }

  def collectPatternVariables[Va](
    pattern: morphir.ir.Value.Pattern[Va]
  ): morphir.sdk.Set.Set[morphir.ir.Name.Name] =
    pattern match {
      case morphir.ir.Value.WildcardPattern(_) =>
        morphir.sdk.Set.empty
      case morphir.ir.Value.AsPattern(_, subject, name) =>
        morphir.sdk.Set.insert(name)(morphir.ir.Value.collectPatternVariables(subject))
      case morphir.ir.Value.TuplePattern(_, elemPatterns) =>
        morphir.sdk.List.foldl(morphir.sdk.Set.union[Name.Name])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.ir.Value.collectPatternVariables[Va])(elemPatterns))
      case morphir.ir.Value.ConstructorPattern(_, _, argPatterns) =>
        morphir.sdk.List.foldl(morphir.sdk.Set.union[Name.Name])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.ir.Value.collectPatternVariables[Va])(argPatterns))
      case morphir.ir.Value.EmptyListPattern(_) =>
        morphir.sdk.Set.empty
      case morphir.ir.Value.HeadTailPattern(_, headPattern, tailPattern) =>
        morphir.sdk.Set.union(morphir.ir.Value.collectPatternVariables(headPattern))(morphir.ir.Value.collectPatternVariables(tailPattern))
      case morphir.ir.Value.LiteralPattern(_, _) =>
        morphir.sdk.Set.empty
      case morphir.ir.Value.UnitPattern(_) =>
        morphir.sdk.Set.empty
    }

  def collectReferences[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] = {
    def collectUnion(
      values: morphir.sdk.List.List[morphir.ir.Value.Value[Ta, Va]]
    ): morphir.sdk.Set.Set[morphir.ir.FQName.FQName] =
      morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.ir.Value.collectReferences[Ta,Va])(values))

    value match {
      case morphir.ir.Value.Tuple(_, elements) =>
        collectUnion(elements)
      case morphir.ir.Value.List(_, items) =>
        collectUnion(items)
      case morphir.ir.Value.Record(_, fields) =>
        collectUnion(morphir.sdk.Dict.values(fields))
      case morphir.ir.Value.Reference(_, fQName) =>
        morphir.sdk.Set.singleton(fQName)
      case morphir.ir.Value.Field(_, subjectValue, _) =>
        morphir.ir.Value.collectReferences(subjectValue)
      case morphir.ir.Value.Apply(_, function, argument) =>
        collectUnion(morphir.sdk.List(
          function,
          argument
        ))
      case morphir.ir.Value.Lambda(_, _, body) =>
        morphir.ir.Value.collectReferences(body)
      case morphir.ir.Value.LetDefinition(_, _, valueDefinition, inValue) =>
        collectUnion(morphir.sdk.List(
          valueDefinition.body,
          inValue
        ))
      case morphir.ir.Value.LetRecursion(_, valueDefinitions, inValue) =>
        morphir.sdk.List.foldl(morphir.sdk.Set.union[FQName.FQName])(morphir.sdk.Set.empty)(morphir.sdk.List.append(morphir.sdk.List(morphir.ir.Value.collectReferences(inValue)))(morphir.sdk.List.map(({
          case (_, _def) =>
            morphir.ir.Value.collectReferences(_def.body)
        } : ((morphir.ir.Name.Name, morphir.ir.Value.Definition[Ta, Va])) => morphir.sdk.Set.Set[morphir.ir.FQName.FQName]))(morphir.sdk.Dict.toList(valueDefinitions))))
      case morphir.ir.Value.Destructure(_, _, valueToDestruct, inValue) =>
        collectUnion(morphir.sdk.List(
          valueToDestruct,
          inValue
        ))
      case morphir.ir.Value.IfThenElse(_, condition, thenBranch, elseBranch) =>
        collectUnion(morphir.sdk.List(
          condition,
          thenBranch,
          elseBranch
        ))
      case morphir.ir.Value.PatternMatch(_, branchOutOn, cases) =>
        morphir.sdk.Set.union(morphir.ir.Value.collectReferences(branchOutOn))(collectUnion(morphir.sdk.List.map(morphir.sdk.Tuple.second[Pattern[Va], Value[Ta, Va]])(cases)))
      case morphir.ir.Value.UpdateRecord(_, valueToUpdate, fieldsToUpdate) =>
        morphir.sdk.Set.union(morphir.ir.Value.collectReferences(valueToUpdate))(collectUnion(morphir.sdk.Dict.values(fieldsToUpdate)))
      case _ =>
        morphir.sdk.Set.empty
    }
  }

  def collectValueAttributes[Ta, Va](
    v: morphir.ir.Value.Value[Ta, Va]
  ): morphir.sdk.List.List[Va] =
    v match {
      case morphir.ir.Value.Literal(a, _) =>
        morphir.sdk.List(a)
      case morphir.ir.Value.Constructor(a, _) =>
        morphir.sdk.List(a)
      case morphir.ir.Value.Tuple(a, elements) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concatMap(morphir.ir.Value.collectValueAttributes[Ta, Va])(elements))
      case morphir.ir.Value.List(a, items) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concatMap(morphir.ir.Value.collectValueAttributes[Ta, Va])(items))
      case morphir.ir.Value.Record(a, fields) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concatMap(morphir.ir.Value.collectValueAttributes[Ta, Va])(morphir.sdk.Dict.values(fields)))
      case morphir.ir.Value.Variable(a, _) =>
        morphir.sdk.List(a)
      case morphir.ir.Value.Reference(a, _) =>
        morphir.sdk.List(a)
      case morphir.ir.Value.Field(a, subjectValue, _) =>
        morphir.sdk.List.cons(a)(morphir.ir.Value.collectValueAttributes(subjectValue))
      case morphir.ir.Value.FieldFunction(a, _) =>
        morphir.sdk.List(a)
      case morphir.ir.Value.Apply(a, function, argument) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concat(morphir.sdk.List(
          morphir.ir.Value.collectValueAttributes(function),
          morphir.ir.Value.collectValueAttributes(argument)
        )))
      case morphir.ir.Value.Lambda(a, argumentPattern, body) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concat(morphir.sdk.List(
          morphir.ir.Value.collectPatternAttributes(argumentPattern),
          morphir.ir.Value.collectValueAttributes(body)
        )))
      case morphir.ir.Value.LetDefinition(a, _, valueDefinition, inValue) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concat(morphir.sdk.List(
          morphir.ir.Value.collectDefinitionAttributes(valueDefinition),
          morphir.ir.Value.collectValueAttributes(inValue)
        )))
      case morphir.ir.Value.LetRecursion(a, valueDefinitions, inValue) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.append(morphir.sdk.List.concatMap(morphir.sdk.Basics.composeRight(morphir.sdk.Tuple.second[Name.Name, Definition[Ta, Va]])(morphir.ir.Value.collectDefinitionAttributes[Ta, Va]))(morphir.sdk.Dict.toList(valueDefinitions)))(morphir.ir.Value.collectValueAttributes(inValue)))
      case morphir.ir.Value.Destructure(a, pattern, valueToDestruct, inValue) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concat(morphir.sdk.List(
          morphir.ir.Value.collectPatternAttributes(pattern),
          morphir.ir.Value.collectValueAttributes(valueToDestruct),
          morphir.ir.Value.collectValueAttributes(inValue)
        )))
      case morphir.ir.Value.IfThenElse(a, condition, thenBranch, elseBranch) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.concat(morphir.sdk.List(
          morphir.ir.Value.collectValueAttributes(condition),
          morphir.ir.Value.collectValueAttributes(thenBranch),
          morphir.ir.Value.collectValueAttributes(elseBranch)
        )))
      case morphir.ir.Value.PatternMatch(a, branchOutOn, cases) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.append(morphir.ir.Value.collectValueAttributes(branchOutOn))(morphir.sdk.List.concatMap(({
          case (pattern, body) =>
            morphir.sdk.List.concat(morphir.sdk.List(
              morphir.ir.Value.collectPatternAttributes(pattern),
              morphir.ir.Value.collectValueAttributes(body)
            ))
        } : ((morphir.ir.Value.Pattern[Va], morphir.ir.Value.Value[Ta, Va])) => morphir.sdk.List.List[Va]))(cases)))
      case morphir.ir.Value.UpdateRecord(a, valueToUpdate, fieldsToUpdate) =>
        morphir.sdk.List.cons(a)(morphir.sdk.List.append(morphir.ir.Value.collectValueAttributes(valueToUpdate))(morphir.sdk.List.concatMap(morphir.ir.Value.collectValueAttributes[Ta, Va])(morphir.sdk.Dict.values(fieldsToUpdate))))
      case morphir.ir.Value.Unit(a) =>
        morphir.sdk.List(a)
    }

  def collectVariables[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.sdk.Set.Set[morphir.ir.Name.Name] = {
    def collectUnion(
      values: morphir.sdk.List.List[morphir.ir.Value.Value[Ta, Va]]
    ): morphir.sdk.Set.Set[morphir.ir.Name.Name] =
      morphir.sdk.List.foldl(morphir.sdk.Set.union[Name.Name])(morphir.sdk.Set.empty)(morphir.sdk.List.map(morphir.ir.Value.collectVariables[Ta, Va])(values))

    value match {
      case morphir.ir.Value.Tuple(_, elements) =>
        collectUnion(elements)
      case morphir.ir.Value.List(_, items) =>
        collectUnion(items)
      case morphir.ir.Value.Record(_, fields) =>
        collectUnion(morphir.sdk.Dict.values(fields))
      case morphir.ir.Value.Variable(_, name) =>
        morphir.sdk.Set.singleton(name)
      case morphir.ir.Value.Field(_, subjectValue, _) =>
        morphir.ir.Value.collectVariables(subjectValue)
      case morphir.ir.Value.Apply(_, function, argument) =>
        collectUnion(morphir.sdk.List(
          function,
          argument
        ))
      case morphir.ir.Value.Lambda(_, _, body) =>
        morphir.ir.Value.collectVariables(body)
      case morphir.ir.Value.LetDefinition(_, valueName, valueDefinition, inValue) =>
        morphir.sdk.Set.insert(valueName)(collectUnion(morphir.sdk.List(
          valueDefinition.body,
          inValue
        )))
      case morphir.ir.Value.LetRecursion(_, valueDefinitions, inValue) =>
        morphir.sdk.List.foldl(morphir.sdk.Set.union[Name.Name])(morphir.sdk.Set.empty)(morphir.sdk.List.append(morphir.sdk.List(morphir.ir.Value.collectVariables(inValue)))(morphir.sdk.List.map(({
          case (defName, _def) =>
            morphir.sdk.Set.insert(defName)(morphir.ir.Value.collectVariables(_def.body))
        } : ((morphir.ir.Name.Name, morphir.ir.Value.Definition[Ta, Va])) => morphir.sdk.Set.Set[morphir.ir.Name.Name]))(morphir.sdk.Dict.toList(valueDefinitions))))
      case morphir.ir.Value.Destructure(_, _, valueToDestruct, inValue) =>
        collectUnion(morphir.sdk.List(
          valueToDestruct,
          inValue
        ))
      case morphir.ir.Value.IfThenElse(_, condition, thenBranch, elseBranch) =>
        collectUnion(morphir.sdk.List(
          condition,
          thenBranch,
          elseBranch
        ))
      case morphir.ir.Value.PatternMatch(_, branchOutOn, cases) =>
        morphir.sdk.Set.union(morphir.ir.Value.collectVariables(branchOutOn))(collectUnion(morphir.sdk.List.map(morphir.sdk.Tuple.second[Pattern[Va], Value[Ta, Va]])(cases)))
      case morphir.ir.Value.UpdateRecord(_, valueToUpdate, fieldsToUpdate) =>
        morphir.sdk.Set.union(morphir.ir.Value.collectVariables(valueToUpdate))(collectUnion(morphir.sdk.Dict.values(fieldsToUpdate)))
      case _ =>
        morphir.sdk.Set.empty
    }
  }

  def constructor[Ta, Va](
    attributes: Va
  )(
    fullyQualifiedName: morphir.ir.FQName.FQName
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Constructor(
      attributes,
      fullyQualifiedName
    ) : morphir.ir.Value.Value[Ta, Va])

  def constructorPattern[A](
    attributes: A
  )(
    constructorName: morphir.ir.FQName.FQName
  )(
    argumentPatterns: morphir.sdk.List.List[morphir.ir.Value.Pattern[A]]
  ): morphir.ir.Value.Pattern[A] =
    (morphir.ir.Value.ConstructorPattern(
      attributes,
      constructorName,
      argumentPatterns
    ) : morphir.ir.Value.Pattern[A])

  def countValueNodes[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.sdk.Basics.Int =
    morphir.sdk.List.length(morphir.ir.Value.collectValueAttributes(value))

  def definitionToSpecification[Ta, Va](
    _def: morphir.ir.Value.Definition[Ta, Va]
  ): morphir.ir.Value.Specification[Ta] =
    morphir.ir.Value.Specification(
      inputs = morphir.sdk.List.map(({
        case (name, _, tpe) =>
          (name, tpe)
      } : ((morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])) => (morphir.ir.Name.Name, morphir.ir.Type.Type[Ta])))(_def.inputTypes),
      output = _def.outputType
    )

  def definitionToValue[Ta, Va](
    _def: morphir.ir.Value.Definition[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    _def.inputTypes match {
      case Nil =>
        _def.body
      case (firstArgName, va, _) :: restOfArgs =>
        (morphir.ir.Value.Lambda(
          va,
          (morphir.ir.Value.AsPattern(
            va,
            (morphir.ir.Value.WildcardPattern(va) : morphir.ir.Value.Pattern[Va]),
            firstArgName
          ) : morphir.ir.Value.Pattern[Va]),
          morphir.ir.Value.definitionToValue(_def.copy(inputTypes = restOfArgs))
        ) : morphir.ir.Value.Value[Ta, Va])
    }

  def emptyListPattern[A](
    attributes: A
  ): morphir.ir.Value.Pattern[A] =
    (morphir.ir.Value.EmptyListPattern(attributes) : morphir.ir.Value.Pattern[A])

  def field[Ta, Va](
    attributes: Va
  )(
    subjectValue: morphir.ir.Value.Value[Ta, Va]
  )(
    fieldName: morphir.ir.Name.Name
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Field(
      attributes,
      subjectValue,
      fieldName
    ) : morphir.ir.Value.Value[Ta, Va])

  def fieldFunction[Ta, Va](
    attributes: Va
  )(
    fieldName: morphir.ir.Name.Name
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.FieldFunction(
      attributes,
      fieldName
    ) : morphir.ir.Value.Value[Ta, Va])

  def generateUniqueName[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Name.Name = {
    val existingVariableNames: morphir.sdk.Set.Set[morphir.ir.Name.Name] = morphir.ir.Value.collectVariables(value)

    val chars: morphir.sdk.List.List[morphir.sdk.List.List[morphir.sdk.String.String]] = morphir.sdk.List.map(morphir.sdk.List.singleton[String])(morphir.sdk.String.split("""""")("""abcdefghijklmnopqrstuvwxyz"""))

    morphir.sdk.List.head(morphir.sdk.List.filter(((_var: morphir.ir.Name.Name) =>
      morphir.sdk.Basics.not(morphir.sdk.Set.member(_var)(existingVariableNames))))(chars)) match {
      case morphir.sdk.Maybe.Just(name) =>
        name
      case morphir.sdk.Maybe.Nothing =>
        morphir.sdk.List.concat(morphir.sdk.Set.toList(existingVariableNames))
    }
  }

  def headTailPattern[A](
    attributes: A
  )(
    headPattern: morphir.ir.Value.Pattern[A]
  )(
    tailPattern: morphir.ir.Value.Pattern[A]
  ): morphir.ir.Value.Pattern[A] =
    (morphir.ir.Value.HeadTailPattern(
      attributes,
      headPattern,
      tailPattern
    ) : morphir.ir.Value.Pattern[A])

  def ifThenElse[Ta, Va](
    attributes: Va
  )(
    condition: morphir.ir.Value.Value[Ta, Va]
  )(
    thenBranch: morphir.ir.Value.Value[Ta, Va]
  )(
    elseBranch: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.IfThenElse(
      attributes,
      condition,
      thenBranch,
      elseBranch
    ) : morphir.ir.Value.Value[Ta, Va])

  def indexedMapListHelp[A, B](
    f: morphir.sdk.Basics.Int => A => (B, morphir.sdk.Basics.Int)
  )(
    baseIndex: morphir.sdk.Basics.Int
  )(
    elemList: morphir.sdk.List.List[A]
  ): (morphir.sdk.List.List[B], morphir.sdk.Basics.Int) =
    morphir.sdk.List.foldl(((nextElem: A) =>
      ({
        case (elemsSoFar, lastIndexSoFar) =>
          {
            val (mappedElem, lastIndex) = f(morphir.sdk.Basics.add(lastIndexSoFar)(morphir.sdk.Basics.Int(1)))(nextElem)

            (morphir.sdk.List.append(elemsSoFar)(morphir.sdk.List(mappedElem)), lastIndex)
          }
      } : ((morphir.sdk.List.List[B], morphir.sdk.Basics.Int)) => (morphir.sdk.List.List[B], morphir.sdk.Basics.Int))))((morphir.sdk.List(

    ), baseIndex))(elemList)

  def indexedMapPattern[A, B](
    f: morphir.sdk.Basics.Int => A => B
  )(
    baseIndex: morphir.sdk.Basics.Int
  )(
    pattern: morphir.ir.Value.Pattern[A]
  ): (morphir.ir.Value.Pattern[B], morphir.sdk.Basics.Int) =
    pattern match {
      case morphir.ir.Value.WildcardPattern(a) =>
        ((morphir.ir.Value.WildcardPattern(f(baseIndex)(a)) : morphir.ir.Value.Pattern[B]), baseIndex)
      case morphir.ir.Value.AsPattern(a, aliasedPattern, alias) =>
        {
          val (mappedAliasedPattern, lastIndex) = morphir.ir.Value.indexedMapPattern(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(aliasedPattern)

          ((morphir.ir.Value.AsPattern(
            f(baseIndex)(a),
            mappedAliasedPattern,
            alias
          ) : morphir.ir.Value.Pattern[B]), lastIndex)
        }
      case morphir.ir.Value.TuplePattern(a, elemPatterns) =>
        {
          val (mappedElemPatterns, elemsLastIndex) = morphir.ir.Value.indexedMapListHelp(morphir.ir.Value.indexedMapPattern(f))(baseIndex)(elemPatterns)

          ((morphir.ir.Value.TuplePattern(
            f(baseIndex)(a),
            mappedElemPatterns
          ) : morphir.ir.Value.Pattern[B]), elemsLastIndex)
        }
      case morphir.ir.Value.ConstructorPattern(a, fQName, argPatterns) =>
        {
          val (mappedArgPatterns, argPatternsLastIndex) = morphir.ir.Value.indexedMapListHelp(morphir.ir.Value.indexedMapPattern(f))(baseIndex)(argPatterns)

          ((morphir.ir.Value.ConstructorPattern(
            f(baseIndex)(a),
            fQName,
            mappedArgPatterns
          ) : morphir.ir.Value.Pattern[B]), argPatternsLastIndex)
        }
      case morphir.ir.Value.EmptyListPattern(a) =>
        ((morphir.ir.Value.EmptyListPattern(f(baseIndex)(a)) : morphir.ir.Value.Pattern[B]), baseIndex)
      case morphir.ir.Value.HeadTailPattern(a, headPattern, tailPattern) =>
        {
          val (mappedHeadPattern, lastIndexHeadPattern) = morphir.ir.Value.indexedMapPattern(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(headPattern)

          {
            val (mappedTailPattern, lastIndexTailPattern) = morphir.ir.Value.indexedMapPattern(f)(morphir.sdk.Basics.add(lastIndexHeadPattern)(morphir.sdk.Basics.Int(1)))(tailPattern)

            ((morphir.ir.Value.HeadTailPattern(
              f(baseIndex)(a),
              mappedHeadPattern,
              mappedTailPattern
            ) : morphir.ir.Value.Pattern[B]), lastIndexTailPattern)
          }
        }
      case morphir.ir.Value.LiteralPattern(a, lit) =>
        ((morphir.ir.Value.LiteralPattern(
          f(baseIndex)(a),
          lit
        ) : morphir.ir.Value.Pattern[B]), baseIndex)
      case morphir.ir.Value.UnitPattern(a) =>
        ((morphir.ir.Value.UnitPattern(f(baseIndex)(a)) : morphir.ir.Value.Pattern[B]), baseIndex)
    }

  def indexedMapValue[A, B, Ta](
    f: morphir.sdk.Basics.Int => A => B
  )(
    baseIndex: morphir.sdk.Basics.Int
  )(
    value: morphir.ir.Value.Value[Ta, A]
  ): (morphir.ir.Value.Value[Ta, B], morphir.sdk.Basics.Int) =
    value match {
      case morphir.ir.Value.Literal(a, lit) =>
        ((morphir.ir.Value.Literal(
          f(baseIndex)(a),
          lit
        ) : morphir.ir.Value.Value[Ta, B]), baseIndex)
      case morphir.ir.Value.Constructor(a, fullyQualifiedName) =>
        ((morphir.ir.Value.Constructor(
          f(baseIndex)(a),
          fullyQualifiedName
        ) : morphir.ir.Value.Value[Ta, B]), baseIndex)
      case morphir.ir.Value.Tuple(a, elems) =>
        {
          val (mappedElems, elemsLastIndex) = morphir.ir.Value.indexedMapListHelp[Value[Ta, A], Value[Ta, B]](morphir.ir.Value.indexedMapValue(f))(baseIndex)(elems)

          ((morphir.ir.Value.Tuple(
            f(baseIndex)(a),
            mappedElems
          ) : morphir.ir.Value.Value[Ta, B]), elemsLastIndex)
        }
      case morphir.ir.Value.List(a, values) =>
        {
          val (mappedValues, valuesLastIndex) = morphir.ir.Value.indexedMapListHelp[Value[Ta, A], Value[Ta, B]](morphir.ir.Value.indexedMapValue(f))(baseIndex)(values)

          ((morphir.ir.Value.List(
            f(baseIndex)(a),
            mappedValues
          ) : morphir.ir.Value.Value[Ta, B]), valuesLastIndex)
        }
      case morphir.ir.Value.Record(a, fields) =>
        {
          val (mappedFields, valuesLastIndex) = morphir.ir.Value.indexedMapListHelp(((fieldBaseIndex: morphir.sdk.Basics.Int) =>
            ({
              case (fieldName, fieldValue) =>
                {
                  val (mappedFieldValue, lastFieldIndex) = morphir.ir.Value.indexedMapValue(f)(fieldBaseIndex)(fieldValue)

                  ((fieldName, mappedFieldValue), lastFieldIndex)
                }
            } : ((morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, A])) => ((morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, B]), morphir.sdk.Basics.Int))))(baseIndex)(morphir.sdk.Dict.toList(fields))

          ((morphir.ir.Value.Record(
            f(baseIndex)(a),
            morphir.sdk.Dict.fromList(mappedFields)
          ) : morphir.ir.Value.Value[Ta, B]), valuesLastIndex)
        }
      case morphir.ir.Value.Variable(a, name) =>
        ((morphir.ir.Value.Variable(
          f(baseIndex)(a),
          name
        ) : morphir.ir.Value.Value[Ta, B]), baseIndex)
      case morphir.ir.Value.Reference(a, fQName) =>
        ((morphir.ir.Value.Reference(
          f(baseIndex)(a),
          fQName
        ) : morphir.ir.Value.Value[Ta, B]), baseIndex)
      case morphir.ir.Value.Field(a, subjectValue, name) =>
        {
          val (mappedSubjectValue, subjectValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(subjectValue)

          ((morphir.ir.Value.Field(
            f(baseIndex)(a),
            mappedSubjectValue,
            name
          ) : morphir.ir.Value.Value[Ta, B]), subjectValueLastIndex)
        }
      case morphir.ir.Value.FieldFunction(a, name) =>
        ((morphir.ir.Value.FieldFunction(
          f(baseIndex)(a),
          name
        ) : morphir.ir.Value.Value[Ta, B]), baseIndex)
      case morphir.ir.Value.Apply(a, funValue, argValue) =>
        {
          val (mappedFunValue, funValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(funValue)

          {
            val (mappedArgValue, argValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(funValueLastIndex)(morphir.sdk.Basics.Int(1)))(argValue)

            ((morphir.ir.Value.Apply(
              f(baseIndex)(a),
              mappedFunValue,
              mappedArgValue
            ) : morphir.ir.Value.Value[Ta, B]), argValueLastIndex)
          }
        }
      case morphir.ir.Value.Lambda(a, argPattern, bodyValue) =>
        {
          val (mappedArgPattern, argPatternLastIndex) = morphir.ir.Value.indexedMapPattern(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(argPattern)

          {
            val (mappedBodyValue, bodyValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(argPatternLastIndex)(morphir.sdk.Basics.Int(1)))(bodyValue)

            ((morphir.ir.Value.Lambda(
              f(baseIndex)(a),
              mappedArgPattern,
              mappedBodyValue
            ) : morphir.ir.Value.Value[Ta, B]), bodyValueLastIndex)
          }
        }
      case morphir.ir.Value.LetDefinition(a, defName, _def, inValue) =>
        {
          val (mappedDefArgs, defArgsLastIndex) = morphir.ir.Value.indexedMapListHelp(((inputBaseIndex: morphir.sdk.Basics.Int) =>
            ({
              case (inputName, inputA, inputType) =>
                ((inputName, f(inputBaseIndex)(inputA), inputType), inputBaseIndex)
            } : ((morphir.ir.Name.Name, A, morphir.ir.Type.Type[Ta])) => ((morphir.ir.Name.Name, B, morphir.ir.Type.Type[Ta]), morphir.sdk.Basics.Int))))(baseIndex)(_def.inputTypes)

          {
            val (mappedDefBody, defBodyLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(defArgsLastIndex)(morphir.sdk.Basics.Int(1)))(_def.body)

            {
              val mappedDef: morphir.ir.Value.Definition[Ta, B] = morphir.ir.Value.Definition(
                body = mappedDefBody,
                inputTypes = mappedDefArgs,
                outputType = _def.outputType
              )

              {
                val (mappedInValue, inValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(defBodyLastIndex)(morphir.sdk.Basics.Int(1)))(inValue)

                ((morphir.ir.Value.LetDefinition(
                  f(baseIndex)(a),
                  defName,
                  mappedDef,
                  mappedInValue
                ) : morphir.ir.Value.Value[Ta, B]), inValueLastIndex)
              }
            }
          }
        }
      case morphir.ir.Value.LetRecursion(a, defs, inValue) =>
        {
          val (mappedDefs, defsLastIndex) = if (morphir.sdk.Dict.isEmpty(defs)) {
            (morphir.sdk.List(

            ), baseIndex)
          } else {
            morphir.ir.Value.indexedMapListHelp(((defBaseIndex: morphir.sdk.Basics.Int) =>
              ({
                case (defName, _def) =>
                  {
                    val (mappedDefArgs, defArgsLastIndex) = morphir.ir.Value.indexedMapListHelp(((inputBaseIndex: morphir.sdk.Basics.Int) =>
                      ({
                        case (inputName, inputA, inputType) =>
                          ((inputName, f(inputBaseIndex)(inputA), inputType), inputBaseIndex)
                      } : ((morphir.ir.Name.Name, A, morphir.ir.Type.Type[Ta])) => ((morphir.ir.Name.Name, B, morphir.ir.Type.Type[Ta]), morphir.sdk.Basics.Int))))(morphir.sdk.Basics.subtract(defBaseIndex)(morphir.sdk.Basics.Int(1)))(_def.inputTypes)

                    {
                      val (mappedDefBody, defBodyLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(defArgsLastIndex)(morphir.sdk.Basics.Int(1)))(_def.body)

                      {
                        val mappedDef: morphir.ir.Value.Definition[Ta, B] = morphir.ir.Value.Definition(
                          body = mappedDefBody,
                          inputTypes = mappedDefArgs,
                          outputType = _def.outputType
                        )

                        ((defName, mappedDef), defBodyLastIndex)
                      }
                    }
                  }
              } : ((morphir.ir.Name.Name, morphir.ir.Value.Definition[Ta, A])) => ((morphir.ir.Name.Name, morphir.ir.Value.Definition[Ta, B]), morphir.sdk.Basics.Int))))(baseIndex)(morphir.sdk.Dict.toList(defs))
          }

          {
            val (mappedInValue, inValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(defsLastIndex)(morphir.sdk.Basics.Int(1)))(inValue)

            ((morphir.ir.Value.LetRecursion(
              f(baseIndex)(a),
              morphir.sdk.Dict.fromList(mappedDefs),
              mappedInValue
            ) : morphir.ir.Value.Value[Ta, B]), inValueLastIndex)
          }
        }
      case morphir.ir.Value.Destructure(a, bindPattern, bindValue, inValue) =>
        {
          val (mappedBindPattern, bindPatternLastIndex) = morphir.ir.Value.indexedMapPattern(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(bindPattern)

          {
            val (mappedBindValue, bindValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(bindPatternLastIndex)(morphir.sdk.Basics.Int(1)))(bindValue)

            {
              val (mappedInValue, inValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(bindValueLastIndex)(morphir.sdk.Basics.Int(1)))(inValue)

              ((morphir.ir.Value.Destructure(
                f(baseIndex)(a),
                mappedBindPattern,
                mappedBindValue,
                mappedInValue
              ) : morphir.ir.Value.Value[Ta, B]), inValueLastIndex)
            }
          }
        }
      case morphir.ir.Value.IfThenElse(a, condValue, thenValue, elseValue) =>
        {
          val (mappedCondValue, condValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(condValue)

          {
            val (mappedThenValue, thenValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(condValueLastIndex)(morphir.sdk.Basics.Int(1)))(thenValue)

            {
              val (mappedElseValue, elseValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(thenValueLastIndex)(morphir.sdk.Basics.Int(1)))(elseValue)

              ((morphir.ir.Value.IfThenElse(
                f(baseIndex)(a),
                mappedCondValue,
                mappedThenValue,
                mappedElseValue
              ) : morphir.ir.Value.Value[Ta, B]), elseValueLastIndex)
            }
          }
        }
      case morphir.ir.Value.PatternMatch(a, subjectValue, cases) =>
        {
          val (mappedSubjectValue, subjectValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(subjectValue)

          {
            val (mappedCases, casesLastIndex) = morphir.ir.Value.indexedMapListHelp(((fieldBaseIndex: morphir.sdk.Basics.Int) =>
              ({
                case (casePattern, caseBody) =>
                  {
                    val (mappedCasePattern, casePatternLastIndex) = morphir.ir.Value.indexedMapPattern(f)(fieldBaseIndex)(casePattern)

                    {
                      val (mappedCaseBody, caseBodyLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(casePatternLastIndex)(morphir.sdk.Basics.Int(1)))(caseBody)

                      ((mappedCasePattern, mappedCaseBody), caseBodyLastIndex)
                    }
                  }
              } : ((morphir.ir.Value.Pattern[A], morphir.ir.Value.Value[Ta, A])) => ((morphir.ir.Value.Pattern[B], morphir.ir.Value.Value[Ta, B]), morphir.sdk.Basics.Int))))(morphir.sdk.Basics.add(subjectValueLastIndex)(morphir.sdk.Basics.Int(1)))(cases)

            ((morphir.ir.Value.PatternMatch(
              f(baseIndex)(a),
              mappedSubjectValue,
              mappedCases
            ) : morphir.ir.Value.Value[Ta, B]), casesLastIndex)
          }
        }
      case morphir.ir.Value.UpdateRecord(a, subjectValue, fields) =>
        {
          val (mappedSubjectValue, subjectValueLastIndex) = morphir.ir.Value.indexedMapValue(f)(morphir.sdk.Basics.add(baseIndex)(morphir.sdk.Basics.Int(1)))(subjectValue)

          {
            val (mappedFields, valuesLastIndex) = morphir.ir.Value.indexedMapListHelp(((fieldBaseIndex: morphir.sdk.Basics.Int) =>
              ({
                case (fieldName, fieldValue) =>
                  {
                    val (mappedFieldValue, lastFieldIndex) = morphir.ir.Value.indexedMapValue(f)(fieldBaseIndex)(fieldValue)

                    ((fieldName, mappedFieldValue), lastFieldIndex)
                  }
              } : ((morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, A])) => ((morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, B]), morphir.sdk.Basics.Int))))(morphir.sdk.Basics.add(subjectValueLastIndex)(morphir.sdk.Basics.Int(1)))(morphir.sdk.Dict.toList(fields))

            ((morphir.ir.Value.UpdateRecord(
              f(baseIndex)(a),
              mappedSubjectValue,
              morphir.sdk.Dict.fromList(mappedFields)
            ) : morphir.ir.Value.Value[Ta, B]), valuesLastIndex)
          }
        }
      case morphir.ir.Value.Unit(a) =>
        ((morphir.ir.Value.Unit(f(baseIndex)(a)) : morphir.ir.Value.Value[Ta, B]), baseIndex)
    }

  def isData[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.sdk.Basics.Bool =
    value match {
      case morphir.ir.Value.Literal(_, _) =>
        true
      case morphir.ir.Value.Constructor(_, _) =>
        true
      case morphir.ir.Value.Tuple(_, elems) =>
        morphir.sdk.List.all(morphir.ir.Value.isData[Ta, Va])(elems)
      case morphir.ir.Value.List(_, items) =>
        morphir.sdk.List.all(morphir.ir.Value.isData[Ta, Va])(items)
      case morphir.ir.Value.Record(_, fields) =>
        morphir.sdk.List.all(morphir.ir.Value.isData[Ta, Va])(morphir.sdk.Dict.values(fields))
      case morphir.ir.Value.Apply(_, fun, arg) =>
        morphir.sdk.Basics.and(morphir.ir.Value.isData(fun))(morphir.ir.Value.isData(arg))
      case morphir.ir.Value.Unit(_) =>
        true
      case _ =>
        false
    }

  def lambda[Ta, Va](
    attributes: Va
  )(
    argumentPattern: morphir.ir.Value.Pattern[Va]
  )(
    body: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Lambda(
      attributes,
      argumentPattern,
      body
    ) : morphir.ir.Value.Value[Ta, Va])

  def letDef[Ta, Va](
    attributes: Va
  )(
    valueName: morphir.ir.Name.Name
  )(
    valueDefinition: morphir.ir.Value.Definition[Ta, Va]
  )(
    inValue: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.LetDefinition(
      attributes,
      valueName,
      valueDefinition,
      inValue
    ) : morphir.ir.Value.Value[Ta, Va])

  def letDestruct[Ta, Va](
    attributes: Va
  )(
    pattern: morphir.ir.Value.Pattern[Va]
  )(
    valueToDestruct: morphir.ir.Value.Value[Ta, Va]
  )(
    inValue: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Destructure(
      attributes,
      pattern,
      valueToDestruct,
      inValue
    ) : morphir.ir.Value.Value[Ta, Va])

  def letRec[Ta, Va](
    attributes: Va
  )(
    valueDefinitions: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Value.Definition[Ta, Va]]
  )(
    inValue: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.LetRecursion(
      attributes,
      valueDefinitions,
      inValue
    ) : morphir.ir.Value.Value[Ta, Va])

  def list[Ta, Va](
    attributes: Va
  )(
    items: morphir.sdk.List.List[morphir.ir.Value.Value[Ta, Va]]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.List(
      attributes,
      items
    ) : morphir.ir.Value.Value[Ta, Va])

  def literal[Ta, Va](
    attributes: Va
  )(
    value: morphir.ir.Literal.Literal
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Literal(
      attributes,
      value
    ) : morphir.ir.Value.Value[Ta, Va])

  def literalPattern[A](
    attributes: A
  )(
    value: morphir.ir.Literal.Literal
  ): morphir.ir.Value.Pattern[A] =
    (morphir.ir.Value.LiteralPattern(
      attributes,
      value
    ) : morphir.ir.Value.Pattern[A])

  def mapDefinition[E, Ta, Va](
    mapType: morphir.ir.Type.Type[Ta] => morphir.sdk.Result.Result[E, morphir.ir.Type.Type[Ta]]
  )(
    mapValue: morphir.ir.Value.Value[Ta, Va] => morphir.sdk.Result.Result[E, morphir.ir.Value.Value[Ta, Va]]
  )(
    _def: morphir.ir.Value.Definition[Ta, Va]
  ): morphir.sdk.Result.Result[morphir.sdk.List.List[E], morphir.ir.Value.Definition[Ta, Va]] =
    morphir.sdk.Result.map3(((inputTypes: morphir.sdk.List.List[(morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])], outputType: morphir.ir.Type.Type[Ta], body: morphir.ir.Value.Value[Ta, Va]) =>
      (morphir.ir.Value.Definition(
        inputTypes,
        outputType,
        body
      ): morphir.ir.Value.Definition[Ta, Va])))(morphir.sdk.ResultList.keepAllErrors(morphir.sdk.List.map(({
      case (name, attr, tpe) =>
        morphir.sdk.Result.map(((t: morphir.ir.Type.Type[Ta]) =>
          (name, attr, t)))(mapType(tpe))
    } : ((morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])) => morphir.sdk.Result.Result[E, (morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])]))(_def.inputTypes)))(morphir.sdk.Result.mapError(morphir.sdk.List.singleton[E])(mapType(_def.outputType)))(morphir.sdk.Result.mapError(morphir.sdk.List.singleton[E])(mapValue(_def.body)))

  def mapDefinitionAttributes[Ta, Tb, Va, Vb](
    f: Ta => Tb
  )(
    g: Va => Vb
  )(
    d: morphir.ir.Value.Definition[Ta, Va]
  ): morphir.ir.Value.Definition[Tb, Vb] =
    (morphir.ir.Value.Definition(
      morphir.sdk.List.map(({
        case (name, attr, tpe) =>
          (name, g(attr), morphir.ir.Type.mapTypeAttributes(f)(tpe))
      } : ((morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])) => (morphir.ir.Name.Name, Vb, morphir.ir.Type.Type[Tb])))(d.inputTypes),
      morphir.ir.Type.mapTypeAttributes(f)(d.outputType),
      morphir.ir.Value.mapValueAttributes(f)(g)(d.body)
    ) : morphir.ir.Value.Definition[Tb, Vb])

  def mapPatternAttributes[A, B](
    f: A => B
  )(
    p: morphir.ir.Value.Pattern[A]
  ): morphir.ir.Value.Pattern[B] =
    p match {
      case morphir.ir.Value.WildcardPattern(a) =>
        (morphir.ir.Value.WildcardPattern(f(a)) : morphir.ir.Value.Pattern[B])
      case morphir.ir.Value.AsPattern(a, p2, name) =>
        (morphir.ir.Value.AsPattern(
          f(a),
          morphir.ir.Value.mapPatternAttributes(f)(p2),
          name
        ) : morphir.ir.Value.Pattern[B])
      case morphir.ir.Value.TuplePattern(a, elementPatterns) =>
        (morphir.ir.Value.TuplePattern(
          f(a),
          morphir.sdk.List.map(morphir.ir.Value.mapPatternAttributes(f))(elementPatterns)
        ) : morphir.ir.Value.Pattern[B])
      case morphir.ir.Value.ConstructorPattern(a, constructorName, argumentPatterns) =>
        (morphir.ir.Value.ConstructorPattern(
          f(a),
          constructorName,
          morphir.sdk.List.map(morphir.ir.Value.mapPatternAttributes(f))(argumentPatterns)
        ) : morphir.ir.Value.Pattern[B])
      case morphir.ir.Value.EmptyListPattern(a) =>
        (morphir.ir.Value.EmptyListPattern(f(a)) : morphir.ir.Value.Pattern[B])
      case morphir.ir.Value.HeadTailPattern(a, headPattern, tailPattern) =>
        (morphir.ir.Value.HeadTailPattern(
          f(a),
          morphir.ir.Value.mapPatternAttributes(f)(headPattern),
          morphir.ir.Value.mapPatternAttributes(f)(tailPattern)
        ) : morphir.ir.Value.Pattern[B])
      case morphir.ir.Value.LiteralPattern(a, value) =>
        (morphir.ir.Value.LiteralPattern(
          f(a),
          value
        ) : morphir.ir.Value.Pattern[B])
      case morphir.ir.Value.UnitPattern(a) =>
        (morphir.ir.Value.UnitPattern(f(a)) : morphir.ir.Value.Pattern[B])
    }

  def mapSpecificationAttributes[A, B](
    f: A => B
  )(
    spec: morphir.ir.Value.Specification[A]
  ): morphir.ir.Value.Specification[B] =
    (morphir.ir.Value.Specification(
      morphir.sdk.List.map(({
        case (name, tpe) =>
          (name, morphir.ir.Type.mapTypeAttributes(f)(tpe))
      } : ((morphir.ir.Name.Name, morphir.ir.Type.Type[A])) => (morphir.ir.Name.Name, morphir.ir.Type.Type[B])))(spec.inputs),
      morphir.ir.Type.mapTypeAttributes(f)(spec.output)
    ) : morphir.ir.Value.Specification[B])

  def mapValueAttributes[Ta, Tb, Va, Vb](
    f: Ta => Tb
  )(
    g: Va => Vb
  )(
    v: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Tb, Vb] =
    v match {
      case morphir.ir.Value.Literal(a, value) =>
        (morphir.ir.Value.Literal(
          g(a),
          value
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Constructor(a, fullyQualifiedName) =>
        (morphir.ir.Value.Constructor(
          g(a),
          fullyQualifiedName
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Tuple(a, elements) =>
        (morphir.ir.Value.Tuple(
          g(a),
          morphir.sdk.List.map(morphir.ir.Value.mapValueAttributes(f)(g))(elements)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.List(a, items) =>
        (morphir.ir.Value.List(
          g(a),
          morphir.sdk.List.map(morphir.ir.Value.mapValueAttributes(f)(g))(items)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Record(a, fields) =>
        (morphir.ir.Value.Record(
          g(a),
          morphir.sdk.Dict.map(({
            case _ =>
              ((fieldValue: morphir.ir.Value.Value[Ta, Va]) =>
                morphir.ir.Value.mapValueAttributes(f)(g)(fieldValue))
          } : morphir.ir.Name.Name => morphir.ir.Value.Value[Ta, Va] => morphir.ir.Value.Value[Tb, Vb]))(fields)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Variable(a, name) =>
        (morphir.ir.Value.Variable(
          g(a),
          name
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Reference(a, fullyQualifiedName) =>
        (morphir.ir.Value.Reference(
          g(a),
          fullyQualifiedName
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Field(a, subjectValue, fieldName) =>
        (morphir.ir.Value.Field(
          g(a),
          morphir.ir.Value.mapValueAttributes(f)(g)(subjectValue),
          fieldName
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.FieldFunction(a, fieldName) =>
        (morphir.ir.Value.FieldFunction(
          g(a),
          fieldName
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Apply(a, function, argument) =>
        (morphir.ir.Value.Apply(
          g(a),
          morphir.ir.Value.mapValueAttributes(f)(g)(function),
          morphir.ir.Value.mapValueAttributes(f)(g)(argument)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Lambda(a, argumentPattern, body) =>
        (morphir.ir.Value.Lambda(
          g(a),
          morphir.ir.Value.mapPatternAttributes(g)(argumentPattern),
          morphir.ir.Value.mapValueAttributes(f)(g)(body)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.LetDefinition(a, valueName, valueDefinition, inValue) =>
        (morphir.ir.Value.LetDefinition(
          g(a),
          valueName,
          morphir.ir.Value.mapDefinitionAttributes(f)(g)(valueDefinition),
          morphir.ir.Value.mapValueAttributes(f)(g)(inValue)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.LetRecursion(a, valueDefinitions, inValue) =>
        (morphir.ir.Value.LetRecursion(
          g(a),
          morphir.sdk.Dict.map(({
            case _ =>
              ((_def: morphir.ir.Value.Definition[Ta, Va]) =>
                morphir.ir.Value.mapDefinitionAttributes(f)(g)(_def))
          } : morphir.ir.Name.Name => morphir.ir.Value.Definition[Ta, Va] => morphir.ir.Value.Definition[Tb, Vb]))(valueDefinitions),
          morphir.ir.Value.mapValueAttributes(f)(g)(inValue)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Destructure(a, pattern, valueToDestruct, inValue) =>
        (morphir.ir.Value.Destructure(
          g(a),
          morphir.ir.Value.mapPatternAttributes(g)(pattern),
          morphir.ir.Value.mapValueAttributes(f)(g)(valueToDestruct),
          morphir.ir.Value.mapValueAttributes(f)(g)(inValue)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.IfThenElse(a, condition, thenBranch, elseBranch) =>
        (morphir.ir.Value.IfThenElse(
          g(a),
          morphir.ir.Value.mapValueAttributes(f)(g)(condition),
          morphir.ir.Value.mapValueAttributes(f)(g)(thenBranch),
          morphir.ir.Value.mapValueAttributes(f)(g)(elseBranch)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.PatternMatch(a, branchOutOn, cases) =>
        (morphir.ir.Value.PatternMatch(
          g(a),
          morphir.ir.Value.mapValueAttributes(f)(g)(branchOutOn),
          morphir.sdk.List.map(({
            case (pattern, body) =>
              (morphir.ir.Value.mapPatternAttributes(g)(pattern), morphir.ir.Value.mapValueAttributes(f)(g)(body))
          } : ((morphir.ir.Value.Pattern[Va], morphir.ir.Value.Value[Ta, Va])) => (morphir.ir.Value.Pattern[Vb], morphir.ir.Value.Value[Tb, Vb])))(cases)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.UpdateRecord(a, valueToUpdate, fieldsToUpdate) =>
        (morphir.ir.Value.UpdateRecord(
          g(a),
          morphir.ir.Value.mapValueAttributes(f)(g)(valueToUpdate),
          morphir.sdk.Dict.map(({
            case _ =>
              ((fieldValue: morphir.ir.Value.Value[Ta, Va]) =>
                morphir.ir.Value.mapValueAttributes(f)(g)(fieldValue))
          } : morphir.ir.Name.Name => morphir.ir.Value.Value[Ta, Va] => morphir.ir.Value.Value[Tb, Vb]))(fieldsToUpdate)
        ) : morphir.ir.Value.Value[Tb, Vb])
      case morphir.ir.Value.Unit(a) =>
        (morphir.ir.Value.Unit(g(a)) : morphir.ir.Value.Value[Tb, Vb])
    }

  def patternAttribute[A](
    p: morphir.ir.Value.Pattern[A]
  ): A =
    p match {
      case morphir.ir.Value.WildcardPattern(a) =>
        a
      case morphir.ir.Value.AsPattern(a, _, _) =>
        a
      case morphir.ir.Value.TuplePattern(a, _) =>
        a
      case morphir.ir.Value.ConstructorPattern(a, _, _) =>
        a
      case morphir.ir.Value.EmptyListPattern(a) =>
        a
      case morphir.ir.Value.HeadTailPattern(a, _, _) =>
        a
      case morphir.ir.Value.LiteralPattern(a, _) =>
        a
      case morphir.ir.Value.UnitPattern(a) =>
        a
    }

  def patternMatch[Ta, Va](
    attributes: Va
  )(
    branchOutOn: morphir.ir.Value.Value[Ta, Va]
  )(
    cases: morphir.sdk.List.List[(morphir.ir.Value.Pattern[Va], morphir.ir.Value.Value[Ta, Va])]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.PatternMatch(
      attributes,
      branchOutOn,
      cases
    ) : morphir.ir.Value.Value[Ta, Va])

  def record[Ta, Va](
    attributes: Va
  )(
    fields: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, Va]]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Record(
      attributes,
      fields
    ) : morphir.ir.Value.Value[Ta, Va])

  def reduceValueBottomUp[Accumulator, TypeAttribute, ValueAttribute](
    mapNode: morphir.ir.Value.Value[TypeAttribute, ValueAttribute] => morphir.sdk.List.List[Accumulator] => Accumulator
  )(
    currentValue: morphir.ir.Value.Value[TypeAttribute, ValueAttribute]
  ): Accumulator =
    currentValue match {
      case morphir.ir.Value.Tuple(_, elements) =>
        mapNode(currentValue)(morphir.sdk.List.map(morphir.ir.Value.reduceValueBottomUp(mapNode))(elements))
      case morphir.ir.Value.List(_, items) =>
        mapNode(currentValue)(morphir.sdk.List.map(morphir.ir.Value.reduceValueBottomUp(mapNode))(items))
      case morphir.ir.Value.Record(_, fields) =>
        mapNode(currentValue)(morphir.sdk.List.map(morphir.ir.Value.reduceValueBottomUp(mapNode))(morphir.sdk.Dict.values(fields)))
      case morphir.ir.Value.Field(_, subjectValue, _) =>
        mapNode(currentValue)(morphir.sdk.List(morphir.ir.Value.reduceValueBottomUp(mapNode)(subjectValue)))
      case morphir.ir.Value.Apply(_, function, argument) =>
        mapNode(currentValue)(morphir.sdk.List(
          morphir.ir.Value.reduceValueBottomUp(mapNode)(function),
          morphir.ir.Value.reduceValueBottomUp(mapNode)(argument)
        ))
      case morphir.ir.Value.Lambda(_, _, body) =>
        mapNode(currentValue)(morphir.sdk.List(morphir.ir.Value.reduceValueBottomUp(mapNode)(body)))
      case morphir.ir.Value.LetDefinition(_, _, _, inValue) =>
        mapNode(currentValue)(morphir.sdk.List(morphir.ir.Value.reduceValueBottomUp(mapNode)(inValue)))
      case morphir.ir.Value.LetRecursion(_, _, inValue) =>
        mapNode(currentValue)(morphir.sdk.List(morphir.ir.Value.reduceValueBottomUp(mapNode)(inValue)))
      case morphir.ir.Value.Destructure(_, _, valueToDestruct, inValue) =>
        mapNode(currentValue)(morphir.sdk.List(
          morphir.ir.Value.reduceValueBottomUp(mapNode)(valueToDestruct),
          morphir.ir.Value.reduceValueBottomUp(mapNode)(inValue)
        ))
      case morphir.ir.Value.IfThenElse(_, condition, thenBranch, elseBranch) =>
        mapNode(currentValue)(morphir.sdk.List(
          morphir.ir.Value.reduceValueBottomUp(mapNode)(condition),
          morphir.ir.Value.reduceValueBottomUp(mapNode)(thenBranch),
          morphir.ir.Value.reduceValueBottomUp(mapNode)(elseBranch)
        ))
      case morphir.ir.Value.PatternMatch(_, branchOutOn, cases) =>
        mapNode(currentValue)(morphir.sdk.List.append(morphir.sdk.List(morphir.ir.Value.reduceValueBottomUp(mapNode)(branchOutOn)))(morphir.sdk.List.map(morphir.ir.Value.reduceValueBottomUp(mapNode))(morphir.sdk.List.map(morphir.sdk.Tuple.second[Pattern[ValueAttribute], Value[TypeAttribute, ValueAttribute]])(cases))))
      case morphir.ir.Value.UpdateRecord(_, valueToUpdate, fieldsToUpdate) =>
        mapNode(currentValue)(morphir.sdk.List.append(morphir.sdk.List(morphir.ir.Value.reduceValueBottomUp(mapNode)(valueToUpdate)))(morphir.sdk.List.map(morphir.ir.Value.reduceValueBottomUp(mapNode))(morphir.sdk.Dict.values(fieldsToUpdate))))
      case _ =>
        mapNode(currentValue)(morphir.sdk.List(

        ))
    }

  def reference[Ta, Va](
    attributes: Va
  )(
    fullyQualifiedName: morphir.ir.FQName.FQName
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Reference(
      attributes,
      fullyQualifiedName
    ) : morphir.ir.Value.Value[Ta, Va])

  def replaceVariables[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  )(
    mapping: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, Va]]
  ): morphir.ir.Value.Value[Ta, Va] =
    morphir.ir.Value.rewriteValue(((_val: morphir.ir.Value.Value[Ta, Va]) =>
      _val match {
        case morphir.ir.Value.Variable(_, name) =>
          (morphir.sdk.Maybe.Just(morphir.sdk.Maybe.withDefault(_val)(morphir.sdk.Dict.get(name)(mapping))) : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
        case _ =>
          (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
      }))(value)

  def rewriteMaybeToPatternMatch[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    morphir.ir.Value.rewriteValue(((_val: morphir.ir.Value.Value[Ta, Va]) =>
      _val match {
        case morphir.ir.Value.Apply(tpe, morphir.ir.Value.Apply(_, morphir.ir.Value.Reference(_, ((("""morphir""" :: Nil) :: ("""s""" :: """d""" :: """k""" :: Nil) :: Nil),(("""maybe""" :: Nil) :: Nil), ("""with""" :: """default""" :: Nil))), defaultValue), morphir.ir.Value.Apply(maybetpe, morphir.ir.Value.Apply(_, morphir.ir.Value.Reference(_, ((("""morphir""" :: Nil) :: ("""s""" :: """d""" :: """k""" :: Nil) :: Nil), (("""maybe""" :: Nil) :: Nil), ("""map""" :: Nil))), mapLambda), inputMaybe)) =>
          mapLambda match {
            case morphir.ir.Value.Lambda(_, argPattern, bodyValue) =>
              (morphir.sdk.Maybe.Just((morphir.ir.Value.PatternMatch(
                tpe,
                inputMaybe,
                morphir.sdk.List(
                  ((morphir.ir.Value.ConstructorPattern(
                    maybetpe,
                    (morphir.sdk.List(
                      morphir.sdk.List("""morphir"""),
                      morphir.sdk.List(
                        """s""",
                        """d""",
                        """k"""
                      )
                    ), morphir.sdk.List(morphir.sdk.List("""maybe""")), morphir.sdk.List("""just""")),
                    morphir.sdk.List(argPattern)
                  ) : morphir.ir.Value.Pattern[Va]), morphir.ir.Value.rewriteMaybeToPatternMatch(bodyValue)),
                  ((morphir.ir.Value.ConstructorPattern(
                    maybetpe,
                    (morphir.sdk.List(
                      morphir.sdk.List("""morphir"""),
                      morphir.sdk.List(
                        """s""",
                        """d""",
                        """k"""
                      )
                    ), morphir.sdk.List(morphir.sdk.List("""maybe""")), morphir.sdk.List("""nothing""")),
                    morphir.sdk.List(

                    )
                  ) : morphir.ir.Value.Pattern[Va]), defaultValue)
                )
              ) : morphir.ir.Value.Value[Ta, Va])) : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
            case _ =>
              {
                val argName: Name.Name = morphir.ir.Value.generateUniqueName(mapLambda)

                (morphir.sdk.Maybe.Just((morphir.ir.Value.PatternMatch(
                  tpe,
                  inputMaybe,
                  morphir.sdk.List(
                    ((morphir.ir.Value.ConstructorPattern(
                      maybetpe,
                      (morphir.sdk.List(
                        morphir.sdk.List("""morphir"""),
                        morphir.sdk.List(
                          """s""",
                          """d""",
                          """k"""
                        )
                      ), morphir.sdk.List(morphir.sdk.List("""maybe""")), morphir.sdk.List("""just""")),
                      morphir.sdk.List((morphir.ir.Value.AsPattern(
                        tpe,
                        (morphir.ir.Value.WildcardPattern(tpe) : morphir.ir.Value.Pattern[Va]),
                        argName
                      ) : morphir.ir.Value.Pattern[Va]))
                    ) : morphir.ir.Value.Pattern[Va]), (morphir.ir.Value.Apply(
                      tpe,
                      morphir.ir.Value.rewriteMaybeToPatternMatch(mapLambda),
                      (morphir.ir.Value.Variable(
                        tpe,
                        argName
                      ) : morphir.ir.Value.Value[Ta, Va])
                    ) : morphir.ir.Value.Value[Ta, Va])),
                    ((morphir.ir.Value.ConstructorPattern(
                      maybetpe,
                      (morphir.sdk.List(
                        morphir.sdk.List("""morphir"""),
                        morphir.sdk.List(
                          """s""",
                          """d""",
                          """k"""
                        )
                      ), morphir.sdk.List(morphir.sdk.List("""maybe""")), morphir.sdk.List("""nothing""")),
                      morphir.sdk.List(

                      )
                    ) : morphir.ir.Value.Pattern[Va]), defaultValue)
                  )
                ) : morphir.ir.Value.Value[Ta, Va])) : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
              }
          }
        case _ =>
          (morphir.sdk.Maybe.Nothing : morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]])
      }))(value)

  def rewriteValue[Ta, Va](
    f: morphir.ir.Value.Value[Ta, Va] => morphir.sdk.Maybe.Maybe[morphir.ir.Value.Value[Ta, Va]]
  )(
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Value[Ta, Va] =
    f(value) match {
      case morphir.sdk.Maybe.Just(newValue) =>
        newValue
      case morphir.sdk.Maybe.Nothing =>
        value match {
          case morphir.ir.Value.Tuple(va, elems) =>
            (morphir.ir.Value.Tuple(
              va,
              morphir.sdk.List.map(morphir.ir.Value.rewriteValue(f))(elems)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.List(va, items) =>
            (morphir.ir.Value.List(
              va,
              morphir.sdk.List.map(morphir.ir.Value.rewriteValue(f))(items)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.Record(va, fields) =>
            (morphir.ir.Value.Record(
              va,
              morphir.sdk.Dict.map(({
                case _ =>
                  ((v: morphir.ir.Value.Value[Ta, Va]) =>
                    morphir.ir.Value.rewriteValue(f)(v))
              } : morphir.ir.Name.Name => morphir.ir.Value.Value[Ta, Va] => morphir.ir.Value.Value[Ta, Va]))(fields)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.Field(va, subject, name) =>
            (morphir.ir.Value.Field(
              va,
              morphir.ir.Value.rewriteValue(f)(subject),
              name
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.Apply(va, fun, arg) =>
            (morphir.ir.Value.Apply(
              va,
              morphir.ir.Value.rewriteValue(f)(fun),
              morphir.ir.Value.rewriteValue(f)(arg)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.Lambda(va, pattern, body) =>
            (morphir.ir.Value.Lambda(
              va,
              pattern,
              morphir.ir.Value.rewriteValue(f)(body)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.LetDefinition(va, defName, _def, inValue) =>
            (morphir.ir.Value.LetDefinition(
              va,
              defName,
              _def.copy(body = morphir.ir.Value.rewriteValue(f)(_def.body)),
              morphir.ir.Value.rewriteValue(f)(inValue)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.LetRecursion(va, defs, inValue) =>
            (morphir.ir.Value.LetRecursion(
              va,
              morphir.sdk.Dict.map(({
                case _ =>
                  ((_def: morphir.ir.Value.Definition[Ta, Va]) =>
                    _def.copy(body = morphir.ir.Value.rewriteValue(f)(_def.body)))
              } : morphir.ir.Name.Name => morphir.ir.Value.Definition[Ta, Va] => morphir.ir.Value.Definition[Ta, Va]))(defs),
              morphir.ir.Value.rewriteValue(f)(inValue)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.Destructure(va, bindPattern, bindValue, inValue) =>
            (morphir.ir.Value.Destructure(
              va,
              bindPattern,
              morphir.ir.Value.rewriteValue(f)(bindValue),
              morphir.ir.Value.rewriteValue(f)(inValue)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.IfThenElse(va, condition, thenBranch, elseBranch) =>
            (morphir.ir.Value.IfThenElse(
              va,
              morphir.ir.Value.rewriteValue(f)(condition),
              morphir.ir.Value.rewriteValue(f)(thenBranch),
              morphir.ir.Value.rewriteValue(f)(elseBranch)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.PatternMatch(va, subject, cases) =>
            (morphir.ir.Value.PatternMatch(
              va,
              morphir.ir.Value.rewriteValue(f)(subject),
              morphir.sdk.List.map(({
                case (p, v) =>
                  (p, morphir.ir.Value.rewriteValue(f)(v))
              } : ((morphir.ir.Value.Pattern[Va], morphir.ir.Value.Value[Ta, Va])) => (morphir.ir.Value.Pattern[Va], morphir.ir.Value.Value[Ta, Va])))(cases)
            ) : morphir.ir.Value.Value[Ta, Va])
          case morphir.ir.Value.UpdateRecord(va, subject, fields) =>
            (morphir.ir.Value.UpdateRecord(
              va,
              morphir.ir.Value.rewriteValue(f)(subject),
              morphir.sdk.Dict.map(({
                case _ =>
                  ((v: morphir.ir.Value.Value[Ta, Va]) =>
                    morphir.ir.Value.rewriteValue(f)(v))
              } : morphir.ir.Name.Name => morphir.ir.Value.Value[Ta, Va] => morphir.ir.Value.Value[Ta, Va]))(fields)
            ) : morphir.ir.Value.Value[Ta, Va])
          case _ =>
            value
        }
    }

  def toRawValue[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.RawValue =
    morphir.ir.Value.mapValueAttributes[Ta, Unit, Va, Unit](morphir.sdk.Basics.always[Unit, Ta]({}))(morphir.sdk.Basics.always[Unit, Va]({}))(value)

  def _toString[Ta, Va](
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.sdk.String.String = {
    def literalToString(
      lit: morphir.ir.Literal.Literal
    ): morphir.sdk.String.String =
      lit match {
        case morphir.ir.Literal.BoolLiteral(bool) =>
          if (bool) {
            """True"""
          } else {
            """False"""
          }
        case morphir.ir.Literal.CharLiteral(char) =>
          morphir.sdk.String.concat(morphir.sdk.List(
            """'""",
            morphir.sdk.String.fromChar(char),
            """'"""
          ))
        case morphir.ir.Literal.StringLiteral(string) =>
          morphir.sdk.String.concat(morphir.sdk.List(
            """"""",
            string,
            """""""
          ))
        case morphir.ir.Literal.WholeNumberLiteral(int) =>
          morphir.sdk.String.fromInt(int)
        case morphir.ir.Literal.FloatLiteral(float) =>
          morphir.sdk.String.fromFloat(float)
        case morphir.ir.Literal.DecimalLiteral(decimal) =>
          morphir.sdk.Decimal._toString(decimal)
      }

    {
      def patternToString(
        pattern: morphir.ir.Value.Pattern[Va]
      ): morphir.sdk.String.String =
        pattern match {
          case morphir.ir.Value.WildcardPattern(_) =>
            """_"""
          case morphir.ir.Value.AsPattern(_, morphir.ir.Value.WildcardPattern(_), alias) =>
            morphir.ir.Name.toCamelCase(alias)
          case morphir.ir.Value.AsPattern(_, subjectPattern, alias) =>
            morphir.sdk.String.concat(morphir.sdk.List(
              patternToString(subjectPattern),
              """ as """,
              morphir.ir.Name.toCamelCase(alias)
            ))
          case morphir.ir.Value.TuplePattern(_, elems) =>
            morphir.sdk.String.concat(morphir.sdk.List(
              """( """,
              morphir.sdk.String.join(""", """)(morphir.sdk.List.map(patternToString)(elems)),
              """ )"""
            ))
          case morphir.ir.Value.ConstructorPattern(_, (packageName, moduleName, localName), argPatterns) =>
            {
              val constructorString: morphir.sdk.String.String = morphir.sdk.String.join(""".""")(morphir.sdk.List(
                morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(packageName),
                morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(moduleName),
                morphir.ir.Name.toTitleCase(localName)
              ))

              morphir.sdk.String.join(""" """)(morphir.sdk.List.cons(constructorString)(morphir.sdk.List.map(patternToString)(argPatterns)))
            }
          case morphir.ir.Value.EmptyListPattern(_) =>
            """[]"""
          case morphir.ir.Value.HeadTailPattern(_, headPattern, tailPattern) =>
            morphir.sdk.String.concat(morphir.sdk.List(
              patternToString(headPattern),
              """ :: """,
              patternToString(tailPattern)
            ))
          case morphir.ir.Value.LiteralPattern(_, lit) =>
            literalToString(lit)
          case morphir.ir.Value.UnitPattern(_) =>
            """()"""
        }

      {
        def valueToString(
          v: morphir.ir.Value.Value[Ta, Va]
        ): morphir.sdk.String.String =
          v match {
            case morphir.ir.Value.Literal(_, lit) =>
              literalToString(lit)
            case morphir.ir.Value.Constructor(_, (packageName, moduleName, localName)) =>
              morphir.sdk.String.join(""".""")(morphir.sdk.List(
                morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(packageName),
                morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(moduleName),
                morphir.ir.Name.toTitleCase(localName)
              ))
            case morphir.ir.Value.Tuple(_, elems) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """( """,
                morphir.sdk.String.join(""", """)(morphir.sdk.List.map(morphir.ir.Value._toString[Ta, Va])(elems)),
                """ )"""
              ))
            case morphir.ir.Value.List(_, items) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """[ """,
                morphir.sdk.String.join(""", """)(morphir.sdk.List.map(morphir.ir.Value._toString[Ta, Va])(items)),
                """ ]"""
              ))
            case morphir.ir.Value.Record(_, fields) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """{ """,
                morphir.sdk.String.join(""", """)(morphir.sdk.List.map(({
                  case (fieldName, fieldValue) =>
                    morphir.sdk.String.concat(morphir.sdk.List(
                      morphir.ir.Name.toCamelCase(fieldName),
                      """ = """,
                      morphir.ir.Value._toString(fieldValue)
                    ))
                } : ((morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, Va])) => morphir.sdk.String.String))(morphir.sdk.Dict.toList(fields))),
                """ }"""
              ))
            case morphir.ir.Value.Variable(_, name) =>
              morphir.ir.Name.toCamelCase(name)
            case morphir.ir.Value.Reference(_, (packageName, moduleName, localName)) =>
              morphir.sdk.String.join(""".""")(morphir.sdk.List(
                morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(packageName),
                morphir.ir.Path._toString(morphir.ir.Name.toTitleCase)(""".""")(moduleName),
                morphir.ir.Name.toCamelCase(localName)
              ))
            case morphir.ir.Value.Field(_, subject, fieldName) =>
              morphir.sdk.String.join(""".""")(morphir.sdk.List(
                valueToString(subject),
                morphir.ir.Name.toCamelCase(fieldName)
              ))
            case morphir.ir.Value.FieldFunction(_, fieldName) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """.""",
                morphir.ir.Name.toCamelCase(fieldName)
              ))
            case morphir.ir.Value.Apply(_, fun, arg) =>
              morphir.sdk.String.join(""" """)(morphir.sdk.List(
                morphir.ir.Value._toString(fun),
                morphir.ir.Value._toString(arg)
              ))
            case morphir.ir.Value.Lambda(_, argPattern, body) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """(\""",
                patternToString(argPattern),
                """ -> """,
                valueToString(body),
                """)"""
              ))
            case morphir.ir.Value.LetDefinition(_, name, _def, inValue) =>
              {
                val args: morphir.sdk.List.List[morphir.sdk.String.String] = morphir.sdk.List.map(({
                  case (argName, _, _) =>
                    morphir.ir.Name.toCamelCase(argName)
                } : ((morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])) => morphir.sdk.String.String))(_def.inputTypes)

                morphir.sdk.String.concat(morphir.sdk.List(
                  """let """,
                  morphir.ir.Name.toCamelCase(name),
                  morphir.sdk.String.join(""" """)(args),
                  """ = """,
                  valueToString(_def.body),
                  """ in """,
                  valueToString(inValue)
                ))
              }
            case morphir.ir.Value.LetRecursion(_, defs, inValue) =>
              {
                def args(
                  _def: morphir.ir.Value.Definition[Ta, Va]
                ): morphir.sdk.List.List[morphir.sdk.String.String] =
                  morphir.sdk.List.map(({
                    case (argName, _, _) =>
                      morphir.ir.Name.toCamelCase(argName)
                  } : ((morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])) => morphir.sdk.String.String))(_def.inputTypes)

                val defStrings: morphir.sdk.List.List[morphir.sdk.String.String] = morphir.sdk.List.map(({
                  case (name, _def) =>
                    morphir.sdk.String.concat(morphir.sdk.List(
                      morphir.ir.Name.toCamelCase(name),
                      morphir.sdk.String.join(""" """)(args(_def)),
                      """ = """,
                      valueToString(_def.body)
                    ))
                } : ((morphir.ir.Name.Name, morphir.ir.Value.Definition[Ta, Va])) => morphir.sdk.String.String))(morphir.sdk.Dict.toList(defs))

                morphir.sdk.String.concat(morphir.sdk.List(
                  """let """,
                  morphir.sdk.String.join("""; """)(defStrings),
                  """ in """,
                  valueToString(inValue)
                ))
              }
            case morphir.ir.Value.Destructure(_, bindPattern, bindValue, inValue) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """let """,
                patternToString(bindPattern),
                """ = """,
                valueToString(bindValue),
                """ in """,
                valueToString(inValue)
              ))
            case morphir.ir.Value.IfThenElse(_, cond, thenBranch, elseBranch) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """if """,
                valueToString(cond),
                """ then """,
                valueToString(thenBranch),
                """ else """,
                valueToString(elseBranch)
              ))
            case morphir.ir.Value.PatternMatch(_, subject, cases) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """case """,
                valueToString(subject),
                """ of """,
                morphir.sdk.String.join("""; """)(morphir.sdk.List.map(({
                  case (casePattern, caseBody) =>
                    morphir.sdk.String.concat(morphir.sdk.List(
                      patternToString(casePattern),
                      """ -> """,
                      valueToString(caseBody)
                    ))
                } : ((morphir.ir.Value.Pattern[Va], morphir.ir.Value.Value[Ta, Va])) => morphir.sdk.String.String))(cases))
              ))
            case morphir.ir.Value.UpdateRecord(_, subject, fields) =>
              morphir.sdk.String.concat(morphir.sdk.List(
                """{ """,
                valueToString(subject),
                """ | """,
                morphir.sdk.String.join(""", """)(morphir.sdk.List.map(({
                  case (fieldName, fieldValue) =>
                    morphir.sdk.String.concat(morphir.sdk.List(
                      morphir.ir.Name.toCamelCase(fieldName),
                      """ = """,
                      morphir.ir.Value._toString(fieldValue)
                    ))
                } : ((morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, Va])) => morphir.sdk.String.String))(morphir.sdk.Dict.toList(fields))),
                """ }"""
              ))
            case morphir.ir.Value.Unit(_) =>
              """()"""
          }

        valueToString(value)
      }
    }
  }

  def tuple[Ta, Va](
    attributes: Va
  )(
    elements: morphir.sdk.List.List[morphir.ir.Value.Value[Ta, Va]]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Tuple(
      attributes,
      elements
    ) : morphir.ir.Value.Value[Ta, Va])

  def tuplePattern[A](
    attributes: A
  )(
    elementPatterns: morphir.sdk.List.List[morphir.ir.Value.Pattern[A]]
  ): morphir.ir.Value.Pattern[A] =
    (morphir.ir.Value.TuplePattern(
      attributes,
      elementPatterns
    ) : morphir.ir.Value.Pattern[A])

  def typeAndValueToDefinition[Ta, Va](
    valueType: morphir.ir.Type.Type[Ta]
  )(
    value: morphir.ir.Value.Value[Ta, Va]
  ): morphir.ir.Value.Definition[Ta, Va] = {
    def liftLambdaArguments(
      args: morphir.sdk.List.List[(morphir.ir.Name.Name, Va, morphir.ir.Type.Type[Ta])]
    )(
      bodyType: morphir.ir.Type.Type[Ta]
    )(
      body: morphir.ir.Value.Value[Ta, Va]
    ): morphir.ir.Value.Definition[Ta, Va] =
      (body, bodyType) match {
        case (morphir.ir.Value.Lambda(va, morphir.ir.Value.AsPattern(_, morphir.ir.Value.WildcardPattern(_), argName), lambdaBody), morphir.ir.Type.Function(_, argType, returnType)) =>
          liftLambdaArguments(morphir.sdk.List.append(args)(morphir.sdk.List((argName, va, argType))))(returnType)(lambdaBody)
          // TODO Morphir was unable to resolve ^ this `append` to List.append but rather resolved to Basics.append, why?
        case _ =>
          morphir.ir.Value.Definition(
            body = body,
            inputTypes = args,
            outputType = bodyType
          )
      }

    liftLambdaArguments(morphir.sdk.List(

    ))(valueType)(value)
  }

  def uncurryApply[Ta, Va](
    fun: morphir.ir.Value.Value[Ta, Va]
  )(
    lastArg: morphir.ir.Value.Value[Ta, Va]
  ): (morphir.ir.Value.Value[Ta, Va], morphir.sdk.List.List[morphir.ir.Value.Value[Ta, Va]]) =
    fun match {
      case morphir.ir.Value.Apply(_, nestedFun, nestedArg) =>
        {
          val (f, initArgs) = morphir.ir.Value.uncurryApply(nestedFun)(nestedArg)

          (f, morphir.sdk.List.append(initArgs)(morphir.sdk.List(lastArg)))
        }
      case _ =>
        (fun, morphir.sdk.List(lastArg))
    }

  def unit[Ta, Va](
    attributes: Va
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Unit(attributes) : morphir.ir.Value.Value[Ta, Va])

  def update[Ta, Va](
    attributes: Va
  )(
    valueToUpdate: morphir.ir.Value.Value[Ta, Va]
  )(
    fieldsToUpdate: morphir.sdk.Dict.Dict[morphir.ir.Name.Name, morphir.ir.Value.Value[Ta, Va]]
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.UpdateRecord(
      attributes,
      valueToUpdate,
      fieldsToUpdate
    ) : morphir.ir.Value.Value[Ta, Va])

  def valueAttribute[Ta, Va](
    v: morphir.ir.Value.Value[Ta, Va]
  ): Va =
    v match {
      case morphir.ir.Value.Literal(a, _) =>
        a
      case morphir.ir.Value.Constructor(a, _) =>
        a
      case morphir.ir.Value.Tuple(a, _) =>
        a
      case morphir.ir.Value.List(a, _) =>
        a
      case morphir.ir.Value.Record(a, _) =>
        a
      case morphir.ir.Value.Variable(a, _) =>
        a
      case morphir.ir.Value.Reference(a, _) =>
        a
      case morphir.ir.Value.Field(a, _, _) =>
        a
      case morphir.ir.Value.FieldFunction(a, _) =>
        a
      case morphir.ir.Value.Apply(a, _, _) =>
        a
      case morphir.ir.Value.Lambda(a, _, _) =>
        a
      case morphir.ir.Value.LetDefinition(a, _, _, _) =>
        a
      case morphir.ir.Value.LetRecursion(a, _, _) =>
        a
      case morphir.ir.Value.Destructure(a, _, _, _) =>
        a
      case morphir.ir.Value.IfThenElse(a, _, _, _) =>
        a
      case morphir.ir.Value.PatternMatch(a, _, _) =>
        a
      case morphir.ir.Value.UpdateRecord(a, _, _) =>
        a
      case morphir.ir.Value.Unit(a) =>
        a
    }

  def variable[Ta, Va](
    attributes: Va
  )(
    name: morphir.ir.Name.Name
  ): morphir.ir.Value.Value[Ta, Va] =
    (morphir.ir.Value.Variable(
      attributes,
      name
    ) : morphir.ir.Value.Value[Ta, Va])

  def wildcardPattern[A](
    attributes: A
  ): morphir.ir.Value.Pattern[A] =
    (morphir.ir.Value.WildcardPattern(attributes) : morphir.ir.Value.Pattern[A])

}