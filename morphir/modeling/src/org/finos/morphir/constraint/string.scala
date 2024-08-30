package org.finos.morphir.constraint
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*

object string:
    /// Tests if the input is a valid Elm package name.
    type ValidElmPackageName = DescribedAs[
        Match["^(?<author>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})/(?<name>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})$"], 
        "Should be a valid Elm package name containing an author and a package name separated by a slash."
    ]

    type Identifier = DescribedAs[
        Match["^[a-zA-Z_][a-zA-Z0-9_]*$"],
        "Should be a valid identifier."
    ]

    type CamelCased = DescribedAs[
        Match["^[a-z][a-zA-Z0-9]*$"],
        "Should be a valid camelCased identifier."
    ]

    type PascalCased = DescribedAs[
        Match["^[A-Z][a-zA-Z0-9]*$"],
        "Should be a valid PascalCased identifier."
    ]

    type SnakeCased = DescribedAs[
        Match["^[a-z][a-z0-9_]*$"],
        "Should be a valid snake_cased identifier."
    ]

    type KebabCased = DescribedAs[
        Match["^[a-z][a-z0-9-]*$"],
        "Should be a valid kebab-cased identifier."
    ]
