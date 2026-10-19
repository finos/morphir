# YAML event parser provenance

Adapted from [moonbit-community/yaml.mbt](https://github.com/moonbit-community/yaml.mbt),
commit `64fb8d91d4c4f69c647373e6d1bae9840f370b15` (0.0.8), MIT license, retained in LICENSE.
The upstream parser ports yaml-rust2. This package reuses its grammar and scalar decoding.
Morphir changes expose bounded pull events, refuse profile features before scanning them,
and bound scalar buffers, scanner nesting and token production before growth.
The semantic Morphir YAML profile and IR decoding live in the parent package.
