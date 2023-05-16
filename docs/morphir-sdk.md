---
id: morphir-sdk
---

# The Morphir SDK

The goal of the `Morphir.SDK` module is to provide you the basic building blocks to build your domain model and
business logic. It also serves as a specification for backend developers that describes the minimum set of functionality
each backend implementation should support.

It is generally based on [elm/core/1.0.5](https://package.elm-lang.org/packages/elm/core/1.0.5/) and provides most of
the functionality provided there except for some modules that fall outside the scope of business knowledge modeling:
`Debug`, `Platform`, `Process` and `Task`.

Apart from the modules mentioned above you can use everything that's available in `elm/core/1.0.5` without importing
the `Morphir SDK`. The Elm frontend will simply map those to the corresponding type/function names in the Morphir SDK.

The `Morphir SDK` also provides some features beyond `elm/core/1.0.5`. To use those features you have to import the
specific `Morphir SDK` module. 
