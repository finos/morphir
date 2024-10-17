package org.finos.morphir.std.trees

trait Cursor:
    self =>
    import Cursor.* 
    type NodeType 
    def currentNode:NodeType 
    def gotoFirstChild:Boolean
    def gotoNextSibling:Boolean
    def gotoParent:Boolean    
    def asTyped:Typed[NodeType] = self.asInstanceOf[Typed[NodeType]]
            

object Cursor:
    opaque type Typed[+T] <: Cursor { type NodeType <: T } = Cursor { type NodeType <: T }

    
trait TypedCursorFor[-Self, +Node]:
    def cursor(self:Self):Cursor.Typed[Node]    

