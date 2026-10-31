name = "finos/morphir-workbench-desktop"

version = "0.1.0"

license = "Apache-2.0"

repository = "https://github.com/finos/morphir-moonbit"

readme = "README.md"

description = "Proton desktop host for the shared Morphir workbench"

preferred_target = "native"

supported_targets = "native"

import {
  "moonrockz/moon-lander-core@0.8.0",
  "moonrockz/moon-lander-logging@0.8.0",
  "moonrockz/moon-lander-config@0.8.0",
  "moonrockz/moon-lander-mediator@0.8.0",
  "moonrockz/moon-lander-logging-hosting-async@0.8.0",
  "moonrockz/moon-lander-hosting@0.8.0",
  "moonrockz/moon-lander@0.8.0",
  "finos/morphir-workbench-native-session@0.1.0",
  "finos/morphir-workbench-native@0.1.0",
  "finos/morphir-host@0.1.0",
  "moonbitlang/async@0.22.7",
  "moonbit-community/proton@0.3.4",
  "moonbit-community/proton_contract@0.3.4",
}
