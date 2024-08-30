package org.finos.morphir.modeling.graph

trait Graph:
    type Subject 
    type Predicate
    type Object

    def triples:Iterable[Triple]
    

object Graph:
    // final case class Repr[S, P, O]() extends Graph:
    //     type Subject = S
    //     type Predicate = P
    //     type Object = O 

    //     override def triples: Iterable[Triple] = ???
        
end Graph

trait Dataset:
    type Subject
    type Predicate
    type Object
    type GraphLabel

object Dataset

trait Id:
    type IRI 
    
object Id:
    def apply[I](iri:I):Id = Repr(iri)

    final case class Repr[I](iri:I) extends Id:
        type IRI = I    

trait Triple:
    type Self
    type Subject
    type Predicate
    type Object

    def subject:Subject
    def predicate:Predicate
    def $object:Object
    final inline def obj: Object = $object
    def withSubject(subject:Subject):Self
    def withPredicate(predicate:Predicate):Self
    def withObject($object:Object):Self

end Triple    

object Triple:            
    final case class Repr[S, P, O](
        subject:S, 
        predicate:P, 
        $object:O
    ) extends Triple:
        type Self = Repr[S, P, O]
        type Subject = S
        type Predicate = P
        type Object = O

        def withSubject(subject: Subject): Self = copy(subject = subject)
        def withPredicate(predicate: Predicate): Self = copy(predicate = predicate)
        def withObject($object: Object): Self = copy($object = $object)
end Triple        

trait Quad:
    type Self
    type Subject
    type Predicate
    type Object
    type GraphLabel

    def withSubject(subject:Subject):Self
    def withPredicate(predicate:Predicate):Self
    def withObject($object:Object):Self
    def withGraphLabel(graphLabel:Option[GraphLabel]):Self

object Quad:
    final case class Repr[S, P, O, G](subject:S, predicate:P, $object:O, graphLabel:Option[G]) extends Quad:
        type Self = Repr[S, P, O, G]
        type Subject = S
        type Predicate = P
        type Object = O
        type GraphLabel = G        

        def withSubject(subject: Subject): Self = copy(subject = subject)
        def withPredicate(predicate: Predicate): Self = copy(predicate = predicate)
        def withObject($object: Object): Self = copy($object = $object)
        def withGraphLabel(graphLabel: Option[GraphLabel]): Self = copy(graphLabel = graphLabel)
end Quad


trait AttributeModel:
    self =>
    type Attribute
    type Value
    type Entry <: AttributeEntry {
        type Attribute = self.Attribute
        type Value = self.Value
    }

    def attributes:Iterable[Entry]
    def hasAttribute(attribute:Attribute):Boolean
    def valueOf(attribute:Attribute):Option[Value]
    def valuesOf(attribute:Attribute):List[Value]

    def toGraph[S](subject:S):Graph
    def toDataset[S](subject:S):Dataset

trait AttributeEntry:
    type Attribute
    type Value

    def attribute:Attribute
    def value:Value    