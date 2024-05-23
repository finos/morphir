{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}


module Morphir.SDK.StatefulApp exposing (StatefulApp(..))

{-| API for modeling stateful applications.

@docs StatefulApp

-}


{-| Type that represents a stateful application. The following type parameters allow you to fit it to your use case:

  - **k** - Key that's used to partition commands, events and state.
  - **c** - Type that defines all the commands accepted by the application.
  - **s** - Type that defines the state managed by the application.
  - **e** - Type that defines all the events published by the application.

-}
type StatefulApp k c s e
    = StatefulApp (Maybe s -> c -> ( Maybe s, e ))
