package org.finos.morphir.constraint
import io.github.iltotore.iron.*
import io.github.iltotore.iron.constraint.string.*

object string:
    /// Tests if the input is a valid Elm package name.
    type ValidElmPackageName = DescribedAs[
        Match["^(?<author>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})/(?<name>[-a-zA-Z0-9@:%_\\+.~#?&]{2,})$"], 
        "Should be a valid Elm package name containing an author and a package name separated by a slash."
    ]
