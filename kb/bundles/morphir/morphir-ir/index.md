---
okf_version: "0.2"
title: Morphir IR
description: "The Morphir IR: its data model, naming, canonical serialization and distribution formats."
---

# Morphir IR

The Morphir IR: its data model, naming, canonical serialization and distribution formats. Knowledge here covers the
format itself rather than any one implementation of it, so it applies equally to the Elm, Scala, Rust and MoonBit
toolchains under `ecosystem/`.

## Decisions

* [Names encode initialisms as uppercase segments](/decisions/0001-name-canonicalization-and-initialism-encoding.md) - IR v4 marks an initialism by writing its canonical segment in uppercase, and projects names onto the document tree through a defined escape.
* [Both name encodings are implemented, and the switch gates only the encoder](/decisions/0002-both-name-encodings-behind-one-switch.md) - Implementations carry both canonical name encodings; a compile-time constant selects which one is written, while readers always accept both.
* [The naming codec is modelled in Morphir, with a host-language bootstrap](/decisions/0003-the-naming-codec-is-modelled-in-morphir.md) - The v4 naming codec is expressed as a Morphir model in finos/morphir and drives a shared conformance corpus, while one host implementation remains as the bootstrap.
