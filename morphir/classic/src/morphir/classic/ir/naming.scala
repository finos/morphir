package morphir.classic.ir

object naming:
    type Name = List[String]
    object Name:
        def apply(name: String): Name = List(name)