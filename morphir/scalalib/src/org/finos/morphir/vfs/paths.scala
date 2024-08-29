package org.finos.morphir.vfs

trait GenericPath:
    self =>
    type Self <: GenericPath
    def name:String 
    def basename:String 
    def extension:Option[String]

    /// Creates a new path with the specified name as an immediate child of this path.
    def / (name:String):Self

    /// Combines this path with the specified relative path.
    def / (path:RelPath):Self


sealed trait VPath extends GenericPath:    
    type Self <: VPath
    
sealed trait RelPath extends VPath:
    type Self = RelPath    

sealed trait Path extends VPath:
    type Self = Path 