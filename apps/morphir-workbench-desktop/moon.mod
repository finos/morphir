name = "finos/morphir-workbench-desktop"

version = "0.1.0"

license = "Apache-2.0"

repository = "https://github.com/finos/morphir-moonbit"

readme = "README.md"

description = "Proton desktop host for the shared Morphir workbench"

preferred_target = "native"

supported_targets = "native"

import {
  "finos/morphir-workbench-native-session@0.1.0",
  "finos/morphir-workbench-native@0.1.0",
  "moonbitlang/async@0.22.4",
  "moonbit-community/proton@0.3.4",
  "moonbit-community/proton_contract@0.3.4",
}
