# Setup

Elm's standard testing library is elm-test. You can install it by running the following command \
in your project. It will ask questions, just say yes to everything:

```
elm install elm-explorations/test
```

The next thing you need to do is set up a test framework. We have [Lobo](https://github.com/benansell/lobo) 
available internally. This is how you install it for your project:

```
npm install lobo --save
```

Now make sure you have a `tests` directory in the root of the project and that in your `elm.json` 
it is listed in `source-directories`.

Now you are ready to run the tests:

```
npx lobo --framework=elm-test
```

This will also ask a lot of questions, just say yes to everything (you only need to do this once). In the end 
it will show something like this:

```
==================================== Summary ===================================
  TEST RUN PASSED
  Passed:   0
  Failed:   0

  TEST RUN ARGUMENTS
  runCount:   100
  seed:       3473325025
================================================================================
```

This means we are ready to add tests. You can start by creating a `tests/Tests.elm` with the following content:

```elm
module Tests exposing (..)

import Expect
import Test exposing (Test, test)

testExpectTrue : Test
testExpectTrue =
    test "Expect.true test" <|
        \() ->
            True
                |> Expect.true "Expected true"


testExpectNotEqual : Test
testExpectNotEqual =
    test "Expect Not Equal" <|
        \() ->
            Expect.notEqual "foo" "foobar"
```

Now you are ready to run the tests:

```
npx lobo --framework=elm-test
```

This should report 2 passing tests. Now you are ready to add real tests. For that follow the inestructions here:
[elm-explorations/test](https://package.elm-lang.org/packages/elm-explorations/test/latest/)