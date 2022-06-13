# Working With Codecs in Morphir

In this guide, you will learn about JSON encoders and decoders. We would start with JSON Decoders.

We would cover the following:

1. [Introduction to Encoding/Decoding](#) <br>
2. [JSON Decoder Building Blocks](#) <br>
3. [Combining and Nesting Decoders](#) <br>
4. [JSON Decode Pipeline](#) <br>
5. [Writing Encoders and Decoders in Elm](#) <br>
6. [Standard Codecs in Morphir](#) <br>


### 1. Introduction to JSON Decoders
   First we need to understand what JSON decoding means. If we have some JSON structure, for example:
```json
{
  "firstname" : "John",
  "lastname" : "Doe",
  "age" : 40
}
```



For this structure to be useful in an Elm code, we need to extract the values from this JSON object. Why? Since Elm is a pure functional language, we cannot just pass in a raw JSON structure as it may lead to undesirable side effect. So we need not process the JSON structure and extract the values into Elm data types.

For the example above, we would need two decoders:

Decoder String – to extract the String values
Decoder Int – to extract the Int values
These two decoders are given in the next section.



### 2. Building Decoders
   So how do we build these decoders?

Elm provides little decoders for decoding different data types. These decoders are available in the Json.Decode module.  To use this module you need to install the elm/json library using elm install.

```elm
firstnameDecoder : Decoder String
firstnameDecoder =
field "firstname" string

lastnameDecoder : Decoder String
lastnameDecoder =
field "lastname" string

ageDecoder : Decoder Int
ageDecoder  =
field "age" int
```



So you can see that we can build decoders for various data types. What if we have a custom data type? Let’s see that in the next section.



### 3. Combining and Nesting Decoders
   Assuming we have a custom type Student that has two fields as shown below:

type alias Student =
{ name: String
, age : Int
}


We would like build a decoder that takes a json string  and returns a Student object. To this we need to combine two decoders using the map2 function. This function person object, and the two fields to be decoded. The resulting combined decoder is given below:

```elm
studentDecoder : Decoder Student
studentDecoder =
map2 Student
  (Decode.field "name" string)
  (Decode.field "age" int)
```



So if we use the studentDecoder on
```json
{  "name": "John", 
   "age": 40
}
```

We would have a Student object


Sometimes, we may have JSON objects that have nested objects.  In this case, we need to think about decoders for both the parent structure and the nested structure. For example, the json below is structure with a nested object.

```json
{
  "subject": "Literature in English",
  "department": "Language Studies",
  "student":
  {
    "name": "John Doe",
    "age": 40,
    "location": "Budapest"
  },
  "year": 54
}
```



This structure represents an exam that a student enrols in. The equivalent Elm object is the record below:


```elm
type alias Exam =
{ subject: String
, department: String
, student: Student
, year: Int
}
```


The encoder for this would then use the studentEncoder we built earlier on like this:

```elm
examDecoder =
map4 Exam
(Decode.field "subject" string)
(Decode.field "department" string)
(Decode.field "student" studentDecoder)
(Decode.field "age" int)
```


### 4. JSON Decode Pipeline
JSON Decode pipeline provides a way to build decoders using the pipe operator |>
In this case we don't manually have to write mapN based on the the value N (number of fields).
The JSON Decode Pipeline is available in the JSON.Decode.Pipeline library.
Assuming we have the record type below: 
```elm
type alias Deal =
    { product: Maybe String
    , price: Float
    , quantity: Int
    }
```
We can create the build the decoder using the JSON decode pipeline as follows:

```elm
dealDecoder : Decoder Deal
dealDecoder = 
   Decode.succeed Deal
    |> required "product" string
    |> "price" float
    |> required "quantity" int
```

### 5. Writing Encoders for Records in Elm
Similar to decoders, encoders are used to generate a JSON object (Encode.Value) from an Elm data types. For example, given a the deal object
below, we should be able to generate a JSON structure.

```elm
deal =
    { product = "Corn Flakes"
    , price = 34.5
    , quantity = 40
    }

```
The corresponding JSON structur is given below

```json
{
  "product" : "Corn Flakes",
  "price" : 45.50,
  "quantity" : 20
}
```

The encoder for the Deal object is built as below:
```elm
dealEncoder myDeal =
    Encode.object
        [ ( "product", Encode.string myDeal.product )
        , ("price", Encode.float myDeal.price)
        , ("quantity", Encode.int myDeal.quanity)
        ]
```

The Encode.object method is used to encode an object (record in Elm) into Json structure


### 5. Writing Encoders for Custom Types in Elm
In most cases, you will need to build codecs for your custom types. 
Assuming we have the custom type below that represents an Employee which has three constructors (Doctor, Nurse and Intern.
Each constructor can has a string parameter which is the name of the Employee. The custom type is given below:

```elm
type Employee =
     Doctor String
    |Nurse String
    |Intern String
```

To build the encoder for this custom type, we need to use pattern matching as shown below:
```elm
encodeEmployee: Employee -> Encode.Value    
encodeEmployee employee = 
    case employee of
        Doctor name ->
            Encode.string name

        Nurse name ->
            Encode.string name

        Intern name ->
            Encode.string name
```

