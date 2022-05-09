The ++ operator assumes a type inferencer that can tell the difference between String and List. These are the only
two types that are part of the `appendable` type-class. Until the type inferencer is available we will error out to 
remove ambiguity.