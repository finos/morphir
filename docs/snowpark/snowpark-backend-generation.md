---
id: snowpark-backend-generation
title: Snowpark backend generation
---

# Generation patterns and strategies

The **Snowpark** backend supports two main code generation strategies:

- Generating code that manipulates [DataFrame](https://docs.snowflake.com/en/developer-guide/snowpark/scala/working-with-dataframes) expressions
- Generating "plain" Scala code

The backend identifies a series of patterns for deciding which strategy is used to convert a function. These patterns apply to the way types and function are defined. 

## Type definition patterns

Type definitions in the input **Morphir IR** are classified using the following patterns:

### Records that represent tables

Records are classified as "representing a table definition" according to the types of its members. A type that is compatible with a [DataFrame](https://docs.snowflake.com/en/developer-guide/snowpark/scala/working-with-dataframes) is considered to fall in this category. These types are:

- A basic datatype
  - Int
  - Float
  - Bool
  - String
- A [custom type](https://guide.elm-lang.org/types/custom_types.html)
- A [Maybe](https://package.elm-lang.org/packages/elm/core/latest/Maybe) type used with a DataFrame compatible type
- An [alias](https://guide.elm-lang.org/types/type_aliases) of a DataFrame compatible type

An example of one of these records is the following:

```elm
type alias Employee = 
   { firstName : String
   , lastName : String
   }
```

The **Snowpark** backend generates the following code for each type definition:

```scala
  trait Employee {
  
    def firstName: com.snowflake.snowpark.Column
    
    def lastName: com.snowflake.snowpark.Column
  
  }
  
  object Employee extends Employee{
  
    def firstName: com.snowflake.snowpark.Column =
      com.snowflake.snowpark.functions.col("firstName")
    
    def lastName: com.snowflake.snowpark.Column =
      com.snowflake.snowpark.functions.col("lastName")
    
    val schema = com.snowflake.snowpark.types.StructType(
      com.snowflake.snowpark.types.StructField(
        "FirstName",
        com.snowflake.snowpark.types.StringType,
        false
      ),
      com.snowflake.snowpark.types.StructField(
        "LastName",
        com.snowflake.snowpark.types.StringType,
        false
      )
    )
    
    def createEmptyDataFrame(
      session: com.snowflake.snowpark.Session
    ): com.snowflake.snowpark.DataFrame =
      emptyDataFrameCache.getOrElseUpdate(
        true,
        session.createDataFrame(
          Seq(
          
          ),
          schema
        )
      )
    
    val emptyDataFrameCache: scala.collection.mutable.HashMap[Boolean, com.snowflake.snowpark.DataFrame] = new scala.collection.mutable.HashMap(
    
    )
  
  }
  
  class EmployeeWrapper(
    df: com.snowflake.snowpark.DataFrame
  ) extends Employee{
  
    def firstName: com.snowflake.snowpark.Column =
      df("firstName")
    
    def lastName: com.snowflake.snowpark.Column =
      df("lastName")
  
  }
```

This code includes:

- A [trait](https://docs.scala-lang.org/tour/traits.html) with the definitions of the columns
- A [singleton object](https://docs.scala-lang.org/tour/singleton-objects.html) implementing the trait with the column definitions and an utility method to create an empty DataFrame for the current record
- A column wrapper class implementing the previous trait and giving access to the specific columns of a DataFrame 

### Records representing Scala classes

Records that contain fields that are not compatible with table column definitions are classified as "complex" and are generated as [Scala case classes](https://docs.scala-lang.org/tour/case-classes.html).

Examples of these types are:

- Lists
- Other record definitions
- Functions

For example:

```elm
type alias DataFromCompany 
    = 
      {  employees : List Employee
      ,  departments: List Department
      }
```

This backend generates the following class for this record definition:

```scala
  case class DataFromCompany(
    employees: com.snowflake.snowpark.DataFrame,
    departments: com.snowflake.snowpark.DataFrame
  ){}
```

### Types representing DataFrames

This backend considers lists of "records representing tables" as a [**Snowpark** DataFrame](https://docs.snowflake.com/en/developer-guide/snowpark/scala/working-with-dataframes). For example:


```elm
getEmployeesWithLastName : String -> List Employee -> List Employee
getEmployeesWithLastName lastName employees =
    employees
       |> List.filter (\employee -> employee.lastName == lastName)
```

In this case references to `List Employee` are converted to DataFrames:

```scala
  def getEmployeesWithLastName(
    lastName: com.snowflake.snowpark.Column
  )(
    employees: com.snowflake.snowpark.DataFrame
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.DataFrame = {
    val employeesColumns: myModel.Basic.Employee = new myModel.Basic.EmployeeWrapper(employees)
    
    employees.filter((employeesColumns.lastName) === (lastName))
  }
```

## Custom types

Two patterns are used to process [custom types](https://guide.elm-lang.org/types/custom_types.html). These patterns depend on the presence of parameters for type constructors.

### 1. Custom types without data

Custom types that define constructors without parameters are treated as a `String` (or `CHAR`, `VARCHAR`) column. 

For example:

```elm
type CardinalDirection 
    = North
    | South
    | East
    | West

type alias Directions =
    {
        id : Int,
        direction : CardinalDirection
    }

northDirections : List Directions -> List Directions
northDirections dirs =
    dirs
        |> List.filter (\e -> e.direction == North)
```

In this case it is assumed that the code stored in the `Directions` table has a column of type `VARCHAR` or `CHAR` with text with the name of field. For example:

|  ID |  DIRECTION |
|-----|------------|
| 10  | 'North'    |
| 23  | 'East'     |
| 43  | 'South'    |

As a convenience a Scala object is generated with the definition of the possible values:

```Scala
object CardinalDirection{

def East: com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.lit("East")

def North: com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.lit("North")

def Sourth: com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.lit("South")

def West: com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.lit("West")

}
```
Notice the use of [lit](https://docs.snowflake.com/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/functions$.html#lit(literal:Any):com.snowflake.snowpark.Column) to indicate that we expect a literal string value for each constructor.

This object is used where the value of the possible constructors is used. For example for the definition of `northDirections` above the comparison with `North` is generated as follows:

```Scala
  def northDirections(
    dirs: com.snowflake.snowpark.DataFrame
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.DataFrame = {
    val dirsColumns: myModel.Basic.Directions = new myModel.Basic.DirectionsWrapper(dirs)
    
    dirs.filter((dirsColumns.direction) === (myModel.Basic.CardinalDirection.North))
  }
```

### 2. Custom types with data

This backend uses an [OBJECT column](https://docs.snowflake.com/en/sql-reference/data-types-semistructured#object) to represent custom types that have constructors with parameters. Using this kind of columns allows storing different options allowed by the custom type definition. The encoding of a column is defined as follows:

- Values are encoded as a `JSON` object
- A special property of this object called `"__tag"` is used to determine which variant is used in the current value
- All the parameters in order are stored in properties called `field0`, `field1`, `field2` ... `fieldN`

Given the following custom type definition:

```elm
type TimeRange =
   Zero
   | Seconds Int
   | MinutesAndSeconds Int Int

type alias TasksEstimations =
    {
        taskId : Int,
        estimation : TimeRange 
    }
```

The data for `TaskEstimations` is expected to be stored in a table using an `OBJECT` column:

| TASKID | ESTIMATION                                                        |
|--------|-------------------------------------------------------------------|
|   10   | `{ "__tag": "Zero" }`                                             |
|   20   | `{ "__tag": "MinutesAndSeconds", "field0": 10, "field1": 20 }`    |
|   30   | `{ "__tag": "Seconds", "field0": 2 }`                             |

Pattern matching operations that manipulate values of this type are generated as operations that process JSON expressions following this pattern.

For example:

```elm
getTasksEstimationInSeconds : List TasksEstimations -> List { seconds : Int }
getTasksEstimationInSeconds tasks =
   tasks
        |> List.map (\t -> 
               let
                   seconds =
                        case t.estimation of
                              Zero -> 
                                 0
                              Seconds s ->
                                 s
                              MinutesAndSeconds mins secs ->
                                 mins*60 + secs
               in
               { seconds = seconds })

```

This code is generated as:

```scala
  def getTasksEstimationInSeconds(
    tasks: com.snowflake.snowpark.DataFrame
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.DataFrame = {
    val tasksColumns: myModel.Basic.TasksEstimations = new myModel.Basic.TasksEstimationsWrapper(tasks)
    
    tasks.select(com.snowflake.snowpark.functions.when(
      (tasksColumns.estimation("__tag")) === (com.snowflake.snowpark.functions.lit("Zero")),
      com.snowflake.snowpark.functions.lit(0)
    ).when(
      (tasksColumns.estimation("__tag")) === (com.snowflake.snowpark.functions.lit("Seconds")),
      tasksColumns.estimation("field0")
    ).when(
      (tasksColumns.estimation("__tag")) === (com.snowflake.snowpark.functions.lit("MinutesAndSeconds")),
      ((tasksColumns.estimation("field0")) * (com.snowflake.snowpark.functions.lit(60))) + (tasksColumns.estimation("field1"))
    ).as("seconds"))
  }
```

#### 3. Strategy for generating `Maybe` types

The [Maybe a](https://package.elm-lang.org/packages/elm/core/latest/Maybe) type is assumed to be a nullable database value. This means that the data is expected to be stored as follows:

|  Elm value   |  Value stored in the Database |
|--------------|-------------------------------|
| `Just 10`    |  `10`                         |
| `Nothing`    |  `NULL`                       |


## Function definition patterns

These patterns are based on the input and return types of a function. Two strategies are used: using DataFrame expressions or using Scala expressions. The following sections have more details.

### Code generation using DataFrame expressions manipulation

For functions that receive or return DataFrames, simple types, or records the generation strategy is to generate DataFrame expressions for example:

Given the following functions:

```elm
checkLastName : String -> Employee -> Bool
checkLastName name employee =
   if employee.lastName == name then
      True
   else
      False

getEmployeeWithLastName : String -> List Employee -> List Employee
getEmployeeWithLastName lastName employees =
    employees
       |> List.filter (\e -> checkLastName lastName e)
```

In this case the backend generates the following code:

```scala
  def checkLastName(
    name: com.snowflake.snowpark.Column
  )(
    employee: myModel.Basic.Employee
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.when(
      (employee.lastName) === (name),
      com.snowflake.snowpark.functions.lit(true)
    ).otherwise(com.snowflake.snowpark.functions.lit(false))
  
  def getEmployeeWithLastName(
    lastName: com.snowflake.snowpark.Column
  )(
    employees: com.snowflake.snowpark.DataFrame
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.DataFrame = {
    val employeesColumns: myModel.Basic.Employee = new myModel.Basic.EmployeeWrapper(employees)
    
    employees.filter(myModel.Basic.checkLastName(lastName)(employeesColumns))
  }
```

Notice that language constructs are converted to DataFrame expression. For example in the way the `if` expression was converted to a combination of [`when`](https://docs.snowflake.com/ko/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/functions$.html#when(condition:com.snowflake.snowpark.Column,value:com.snowflake.snowpark.Column):com.snowflake.snowpark.CaseExpr) and [`otherwise`](https://docs.snowflake.com/ko/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/CaseExpr.html#otherwise(value:com.snowflake.snowpark.Column):com.snowflake.snowpark.Column) calls.

### Pattern for functions from values to lists of records

If the function doesn't receive a DataFrame but produces lists of records, the strategy for code generation changes. In this case the pattern assumes that an array of semi-structured objects is being created instead of a DataFrame.

For example:

```elm
type alias Department = {
   name : String
   }

type Buildings 
   = B1
   | B2
   | B3

type alias DeptBuildingClassification = 
      {
         deptName : String,
         building : Buildings
      }

classifyDepartment : Department -> List DeptBuildingClassification
classifyDepartment dept =
   if List.member dept.name ["HR", "IT"]  then
      [ { deptName = dept.name
          , building = B1 } ]
   else if String.startsWith "DEVEL" dept.name   then
      [ { deptName = dept.name
          , building = B2 }
      , { deptName = dept.name
          , building = B3 } ]
   else 
      [ ] 

getBuildings : List Department -> List DeptBuildingClassification
getBuildings depts =
   depts
     |> List.concatMap (\e -> classifyDepartment e)
```

Notice the function `classifyDepartment` which generates a list of records but does not receive a list of records.  In this case the code is generated as:

```scala
  def classifyDepartment(
    dept: myModel.Basic.Department
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.Column =
    com.snowflake.snowpark.functions.when(
      dept.name.in(Seq(
        com.snowflake.snowpark.functions.lit("HR"),
        com.snowflake.snowpark.functions.lit("IT")
      )),
      com.snowflake.snowpark.functions.array_construct(com.snowflake.snowpark.functions.array_construct(
        dept.name,
        myModel.Basic.Buildings.B1
      ))
    ).otherwise(com.snowflake.snowpark.functions.when(
      com.snowflake.snowpark.functions.startswith(
        dept.name,
        com.snowflake.snowpark.functions.lit("DEVEL")
      ),
      com.snowflake.snowpark.functions.array_construct(
        com.snowflake.snowpark.functions.array_construct(
          dept.name,
          myModel.Basic.Buildings.B2
        ),
        com.snowflake.snowpark.functions.array_construct(
          dept.name,
          myModel.Basic.Buildings.B3
        )
      )
    ).otherwise(com.snowflake.snowpark.functions.array_construct(
    
    )))
  
  def getBuildings(
    depts: com.snowflake.snowpark.DataFrame
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): com.snowflake.snowpark.DataFrame = {
    val deptsColumns: myModel.Basic.Department = new myModel.Basic.DepartmentWrapper(depts)
    
    depts.select(myModel.Basic.classifyDepartment(myModel.Basic.Department).as("result")).flatten(com.snowflake.snowpark.functions.col("result")).select(
      com.snowflake.snowpark.functions.as_char(com.snowflake.snowpark.functions.col("value")(0)).as("deptName"),
      com.snowflake.snowpark.functions.col("value")(1).as("building")
    )
  }
```

### Code generation using Scala expressions

When a function receives *"complex"* types as parameters the strategy is changed to use a Scala expression approach.

For example:

```elm
type alias EmployeeSal = 
   { firstName : String
   , lastName : String
   , salary : Float
   }


type alias DataForCompany 
    = 
      {  employees : List EmployeeSal
      ,  departments: List Department
      }

avgSalaries : DataForCompany -> Float
avgSalaries companyData =
   let 
       sum = companyData.employees 
                  |> List.map (\e -> e.salary)
                  |> List.sum
       count = companyData.employees
                  |> List.length
   in
   sum / (toFloat count) 
```

In this case code for `avgSalaries` is going to perform a Scala division operation with the result of two DataFrame operations:

```Scala
  def avgSalaries(
    companyData: myModel.Basic.DataForCompany
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): Double = {
    val sum = companyData.employees.select(myModel.Basic.EmployeeSal.salary.as("result")).select(com.snowflake.snowpark.functions.coalesce(
      com.snowflake.snowpark.functions.sum(com.snowflake.snowpark.functions.col("result")),
      com.snowflake.snowpark.functions.lit(0)
    )).first.get.getDouble(0)
    
    val count = companyData.employees.count
    
    (sum) / (count.toDouble)
  }
```

Code generation for this strategy is meant to be used for code that manipulates the result of performing DataFrame operations. At this moment its coverage is very limited.

## Creation of empty DataFrames

Creating an empty list of table-like records is interpreted as creating an empty DataFrame. For example:

```elm
createDataForTest :  List Employee -> DataFromCompany
createDataForTest emps  =
   { employees = emps , departments = [] }
```

In this case the code is generated as follows:

```scala
  def createDataForTest(
    emps: com.snowflake.snowpark.DataFrame
  )(
    implicit sfSession: com.snowflake.snowpark.Session
  ): mymodel.Basic.DataFromCompany = {
    val empsColumns: mymodel.Basic.Employee = new mymodel.Basic.EmployeeWrapper(emps)
    
    mymodel.Basic.DataFromCompany(
      employees = emps,
      departments = mymodel.Basic.Department.createEmptyDataFrame(sfSession)
    )
  }
```

Notice that this is the main reason for having an `implicit` with the [Session object](https://docs.snowflake.com/en/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/Session.html).
