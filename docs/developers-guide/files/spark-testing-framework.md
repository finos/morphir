## Spark CSV Testing guide 
The purpose of this document is to show how someone can use and edit the spark tests.

## Prerequisites
- Morphir-elm package installed. Installation instructions: [morphir-elm installation](https://github.com/finos/morphir-elm/blob/master/README.md)
- Translate elm source into Morphir IR
- Mill must be installed to run the Scala tests
- elm-test must be installed
- Carried out on a system capable of running shell scripts

### How to generate the test data and run the tests

#### a) How to run the all of tests and generate the test data
- You can generate all the test data and test outputs by running 'gulp build' then 'gulp test' anywhere in the repository. This should generate data in both the test input and output files. Then run the spark tests to ensure the elm tests work as expected.

#### b) How to run the spark tests alone
- You can run the spark tests by running the command './mill spark.test' in `/morphir-elm/tests-integration`. This will give a verbose output for each of the tests. You can only do this after generating the test data and test output data as it doesn't generate them itself.

#### c) How to run the elm tests alone
- You can run the elm tests alone by running 'gulp csvfiles' anywhere in the repository. This will only generate the test data, run the tests and create the CSV outputs of the tests.

### How to create / edit Spark CSV tests

#### 1) Write test
- Write the desired test in `/morphir-elm/tests-integration/spark/model/src/SparkTests/Rules`. The already defined types include : antique (`morphir-elm/tests-integration/spark/model/src/SparkTests/DataDefinition/Persistence/Income/AntiqueShop.elm`), antique subset (`/morphir-elm/tests-integration/spark/model/src/SparkTests/Types.elm`) and the various foo types (`/morphir-elm/tests-integration/spark/elm-tests/src/CsvUtils.elm`). A elm type example can be seen below. If the test does not use one of these types, the type will have to be defined in a sensible place. If the test does use one of these types then steps 2 and 3 can be skipped. An example elm test can also be seen below. The example test takes all of the ExampleType's as an input and returns the longest length out of them.

```
type alias ExampleType =
    { name : String
    , length : Float
    }
```

```
testExampleMax : List ExampleType -> List { foo : Maybe Float }
testExampleMax source =
    source
        |> List.map .length
        |> (\lengths ->
                [ { foo =
                        List.maximum lengths
                  }
                ]
           )

```

#### 2) Write code to generate input test data
- If a new type has been designed for the test then new data of that type needs to be generated to use as an input for the test. This can be done in `/morphir-elm/tests-integration/spark/elm-tests/tests` using some elm code placed in a Generate....elm file. This can be done using the 'flatten' and 'generator' functions defined in GenerateAntiqueTestData.elm. It is simple to create code to generate input data by following the example set by the other Generate....elm files in the same directory. Some example data generation code in elm can be seen below.

```
columnNamesExample : String
columnNamesExample =
    "name,length"


generateExampleName : List String -> List String
generateExampleName =
    generator [ "table", "lamp", "door", "vase" ]

generateExampleLength : List String -> List String
generateExampleLength =
    generator [ "20.89", "2879.99", "644.0", "90.678"]

testExampleDataGeneration : Test
testExampleDataGeneration =
    let
        dataExampleGenerate =
            [ "" ]
                |> generateExampleName
                |> generateExampleLength

        csvExampledata =
            columnNamesExample :: dataExampleGenerate

        _ =
            Debug.log "Example_item_data.csv" csvExampledata
    in
    test "Testing Example generation of data" (\_ -> Expect.equal (List.length csvExampledata) 5)
```

- Then a file must be made in `/morphir-elm/tests-integration/spark/elm-tests/src` which will be the data source for the tests, meaning the data from the CSV files will be copied in to this file and decoded. This is done by creating a file named ...DataSource.elm in the previously mentioned directory. This file must follow a similar structure to the rest of the data source files. Some example elm data source code can be seen below.

```
exampleData : String
exampleData =
    """example
bar
cat
pool
desk
computer
headphones
glass
can
paper

"""


exampleDataSource : Result Error (List ExampleType)
exampleDataSource =
    Decode.decodeCsv Decode.FieldNamesFromFirstRow exampleDecoder exampleData
```

- In order to generate the data and copy it in to the data source file some code must be added to `/morphir-elm/tests-integration/spark/elm-tests/tests/create_csv_files.sh`. This code should generate the input data CSV file, then put speech marks around the data and the copy it in to the data source. There is code already in that file that carries out those steps for other data types and can be used as an example to write new code. Some shell code can be seen below.

```
elm-test GenerateExampleTestData.elm > "$TEST_OUTPUT_DIR/generate_example_test_data.txt"
grep -m1 example_data.csv "$TEST_OUTPUT_DIR/generate_example_test_data.txt" | sed -e 's?example_data.csv: \["??' -e 's?",",?\n?g' -e 's?"]??' > "$SPARK_TEST_DATA_DIR/example_data.csv"

echo -n '    """' | cat - "$SPARK_TEST_DATA_DIR/example_data.csv" > "$TEST_OUTPUT_DIR/example_data.csv.in"
echo '"""' >> "$TEST_OUTPUT_DIR/example_data.csv.in"

cat ../src/ExampleDataSource.elm \
    | sed -e '/^    """/,/^"""/d' \
    | sed -e "/^exampleData =/ r $TEST_OUTPUT_DIR/example_data.csv.in" > "$TEST_OUTPUT_DIR/Temp.elm"
cp "$TEST_OUTPUT_DIR/Temp.elm" ../src/ExampleDataSource.elm
```

#### 3) Write encoders and decoders for the input test data

- If a new type has been created for the new test then it must have an encoder to change it from elm code to CSV output and a decoder which changes it from CSV format to something that can eb used in the elm code. All of the pre-existing encoders and decoders are currently in `/morphir-elm/tests-integration/spark/elm-tests/src/CsvUtils.elm`. A similar structure to the pre- existing encoders and decoders can be followed to create a new encoder and decoder. An example elm decoder and encoder can be seen below.

```
exampleDecoder : Decoder ExampleType
exampleDecoder =
    Decode.into ExampleType
        |> Decode.pipeline (Decode.field "name" Decode.string)
        |> Decode.pipeline (Decode.field "length" Decode.float)


exampleEncoder : List ExampleType -> String
exampleEncoder examples =
    examples
        |> Encode.encode
            { encoder =
                Encode.withFieldNames
                    (\example ->
                        [ ( "name", example.name )
                        , ( "length", String.fromFloat example.length )
                        ]
                    )
            , fieldSeparator = ','
            }
```

#### 4) Write the code that will run the test on the input data and produce an output data csv

- The final step of creating a working elm test is to create a file from where the test will actually be executed from. These files are the ones in `/morphir-elm/tests-integration/spark/elm-tests/tests` that have the name Test....elm. In order to code one for the new test it will need the test data source, the encoder and some other functions defined in TestUtils.elm to run the test. Following a similar structure to the other test files will make it simple to code the elm test file. Some example elm code for running a test can be seen below

```
testForExample: Test
testForExample =
    executeTest "exampleTest" exampleDataSource exampleTest exampleEncoder
```

- Then this elm test file will be used in create_csv_files.sh to run the test automatically. The 'elmTestOutputToCSV' function in create_csv_files.sh will be used to format the output of the test so it looks correct in the CSV file. Following the structure of the other test calls in create_csv_files.sh makes it simple to code a new test call. An example shell script test call can be seen below.

```
elmTestOutputToCsv "TestExample.elm" "exampleTest" 
```

#### 5) Write Scala code to check that the elm tests work as expected

The final step to creating a new test is coding the scala test to check that the elm test is working as expected. This will be done in `/morphir-elm/tests-integration/spark/test/src/...Tests.scala`. The purpose of this code is to ensure that the actual output of the test function and the expected output (stored in `morphir-elm/tests-integration/spark/test/src/spark_test_data/expected_results_....csv`) are the same, if they are then the test works correctly. This is quite simple to code by following the structure of the other Scala tests in that directory. An example Scala test can be seen below.
```
  val example_schema = new StructType()
    .add("name", StringType, false)
    .add("length", FloatType, false)

  val example_data = localTestSession.read.format("csv")
    .option("header", "true")
    .schema(example_schema)
    .load("spark/test/src/spark_test_data/example_data.csv")

  test("exampleTest") {
    val df_expected_results = localTestSession.read.format("csv")
      .option("header", "true")
      .schema(example_schema)
      .load("spark/test/src/spark_test_data/expected_results_exampleTest.csv")
    
    val df_actual_results = TestFileImportName.exampleTest(example_data)


    assert(df_actual_results.columns.length == df_expected_results.columns.length)
    assert (df_actual_results.count == df_expected_results.count)
    assert(df_actual_results.except(df_expected_results).isEmpty && df_expected_results.except(df_actual_results).isEmpty)
  }
```

