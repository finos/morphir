module TestModel.Unions exposing (..)

type FullName
    = Firstname

type Employee
    = Fulltime String

type Person
    = Person String
    | Child String Int