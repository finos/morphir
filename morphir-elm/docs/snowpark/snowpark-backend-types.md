---
id: snowpark-backend-types
title: Type mappings
---

# Type mappings

 When generating code using DataFrame operations types are mapped using the following criteria:

| Elm/Morphir-IR type               | Generated Scala type           | Expected Snowflake type                                                                                            |
|-----------------------------------|--------------------------------|--------------------------------------------------------------------------------------------------------------------|
| `Int`                             | `Column`\*                     | [INT](https://docs.snowflake.com/en/sql-reference/data-types-numeric#int-integer-bigint-smallint-tinyint-byteint)  |
| `Float`                           | `Column`\*                     | [DOUBLE](https://docs.snowflake.com/en/sql-reference/data-types-numeric#double-double-precision-real)              |
| `Bool`                            | `Column`\*                     | [BOOLEAN](https://docs.snowflake.com/en/sql-reference/data-types-logical#boolean)                                  |
| `String`                          | `Column`\*                     | [VARCHAR](https://docs.snowflake.com/en/sql-reference/data-types-text)                                             |
| Custom types without parameters   | `Column`\*                     | [VARCHAR](https://docs.snowflake.com/en/sql-reference/data-types-text)                                             | 
| Custom types with parameters      | `Column`\*                     | [OBJECT](https://docs.snowflake.com/en/sql-reference/data-types-semistructured#object)                             |
| Type alias                        | *As aliased*                   | *As aliased*                                                                                                       |
| Record                            | Columns wrapper or **Column**  | N/A                                                                                                                |
| List of Record representing table | `DataFrame`\*\*                | N/A                                                                                                                | 

\* Snowpark [Column](https://docs.snowflake.com/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/Column.html).

\*\* Snowpark [DataFrame](https://docs.snowflake.com/developer-guide/snowpark/reference/scala/com/snowflake/snowpark/DataFrame.html).


When generating the code using Scala expressions the type conversion generates:

| Elm/Morphir-IR type               | Generated Scala type           |
|-----------------------------------|--------------------------------|
| `Int`                             | `Int`                          |
| `Float`                           | `Double`                       |
| `Bool`                            | `Boolean`                      |
| `String`                          | `String`                       |
| Custom types without parameters   | `String`                       |
| Custom types with parameters      | **NOT IMPLEMENTED**            |
| Type alias                        | *As aliased*                   |
| Record                            | Columns wrapper or **Column**  |
| List of Record representing table | `DataFrame`                    |
| Complex Record                    | Scala case class               |
