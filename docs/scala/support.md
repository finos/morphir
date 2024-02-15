---
id: morphir-scala-support
title: Morphir Scala Support
---

This page details which Morphir-Elm features are currently supported.

## SDK Compatibility
This section lists the SDK types and functions currently supported in this version of Morphir-Scala.

### Morphir.SDK.Aggregate
| Function                 | Morphir-Elm Version Introduced | Supported |
|--------------------------|--------------------------------|-----------|
| groupBy                  | v2.65.1                        | &#x2715;  |
| aggregate                | v2.65.1                        | &#x2715;  |
| aggregateMap             | v2.19.0                        | &#x2715;  |
| aggregateMap2            | v2.19.0                        | &#x2715;  |
| aggregateMap3            | v2.19.0                        | &#x2715;  |
| aggregateMap4            | v2.68.0                        | &#x2715;  |
| count                    | v2.19.0                        | &#x2715;  |
| sumOf                    | v2.19.0                        | &#x2715;  |
| minimumOf                | v2.19.0                        | &#x2715;  |
| maximumOf                | v2.19.0                        | &#x2715;  |
| averageOf                | v2.19.0                        | &#x2715;  |
| weightedAverageOf        | v2.19.0                        | &#x2715;  |
| byKey                    | v2.19.0                        | &#x2715;  |
| withFilter               | v2.19.0                        | &#x2715;  |
| constructAggregationCall | v2.66.0                        | &#x2715;  |

### Morphir.SDK.Basics

#### Bool
| Function | Morphir-Elm Version Introduced | Supported |
|----------|--------------------------------|-----------|
| not      | v0.4.0                         | &#x2713;  |
| and      | v0.4.0                         | &#x2713;  |
| or       | v0.4.0                         | &#x2713;  |
| xor      | v0.4.0                         | &#x2713;  |

#### Char
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2715;  |
| lessThanOrEqual    | v2.0.0                         | &#x2715;  |
| greaterThanOrEqual | v2.0.0                         | &#x2715;  |
| max                | v2.0.0                         | &#x2715;  |
| min                | v2.0.0                         | &#x2715;  |
| compare            | v2.0.0                         | &#x2713;  |

#### Float
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| divide             | v0.4.0                         | &#x2713;  |
| round              | v0.4.0                         | &#x2715;  |
| floor              | v0.4.0                         | &#x2715;  |
| ceiling            | v0.4.0                         | &#x2715;  |
| truncate           | v0.4.0                         | &#x2715;  |
| isNan              | v0.4.0                         | &#x2715;  |
| isInfinite         | v0.4.0                         | &#x2715;  |
| e                  | v0.4.0                         | &#x2713;  |
| pi                 | v0.4.0                         | &#x2713;  |
| cos                | v0.4.0                         | &#x2715;  |
| sin                | v0.4.0                         | &#x2715;  |
| tan                | v0.4.0                         | &#x2715;  |
| acos               | v0.4.0                         | &#x2715;  |
| asin               | v0.4.0                         | &#x2715;  |
| atan               | v0.4.0                         | &#x2715;  |
| atan2              | v0.4.0                         | &#x2715;  |
| degrees            | v2.0.0                         | &#x2715;  | 
| radians            | v2.0.0                         | &#x2715;  | 
| turns              | v2.0.0                         | &#x2715;  | 
| toPolar            | v2.0.0                         | &#x2715;  | 
| fromPolar          | v2.0.0                         | &#x2715;  | 
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2715;  |
| lessThanOrEqual    | v2.0.0                         | &#x2715;  |
| greaterThanOrEqual | v2.0.0                         | &#x2715;  |
| max                | v2.0.0                         | &#x2715;  |
| min                | v2.0.0                         | &#x2715;  |
| compare            | v2.0.0                         | &#x2713;  |

#### Int
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| integerDivide      | v0.4.0                         | &#x2713;  |
| toFloat            | v2.0.0                         | &#x2713;  |
| modBy              | v0.4.0                         | &#x2713;  |
| remainderBy        | v0.4.0                         | &#x2713;  |
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2713;  |
| lessThanOrEqual    | v2.0.0                         | &#x2713;  |
| greaterThanOrEqual | v2.0.0                         | &#x2713;  |
| max                | v2.0.0                         | &#x2715;  |
| min                | v2.0.0                         | &#x2715;  |
| compare            | v2.0.0                         | &#x2713;  |

#### List
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| append             | v2.0.0                         | &#x2713;  |
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2715;  |
| lessThanOrEqual    | v2.0.0                         | &#x2715;  |
| greaterThanOrEqual | v2.0.0                         | &#x2715;  |
| max                | v2.0.0                         | &#x2715;  |
| min                | v2.0.0                         | &#x2715;  |
| compare            | v2.0.0                         | &#x2713;  |

#### Number
| Function   | Morphir-Elm Version Introduced | Supported |
|------------|--------------------------------|-----------|
| add        | v2.10.0                        | &#x2715;  |
| subtract   | v2.11.0                        | &#x2715;  |
| multiply   | v2.11.0                        | &#x2715;  |
| divide     | v2.10.0                        | &#x2715;  |
| power      | v2.0.0                         | &#x2715;  |
| negate     | v2.11.0                        | &#x2715;  |
| abs        | v2.11.0                        | &#x2715;  |
| clamp      | v2.0.0                         | &#x2715;  |

#### String
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| append             | v2.0.0                         | &#x2715;  |
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2715;  |
| lessThanOrEqual    | v2.0.0                         | &#x2715;  |
| greaterThanOrEqual | v2.0.0                         | &#x2715;  |
| max                | v2.0.0                         | &#x2715;  |
| min                | v2.0.0                         | &#x2715;  |
| compare            | v2.0.0                         | &#x2713;  |

#### Tuple
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2715;  |
| lessThanOrEqual    | v2.0.0                         | &#x2715;  |
| greaterThanOrEqual | v2.0.0                         | &#x2715;  |
| max                | v2.0.0                         | &#x2715;  |
| min                | v2.0.0                         | &#x2715;  |
| compare            | v2.0.0                         | &#x2713;  |


### Morphir.SDK.Bool
| Function | Morphir-Elm Version Introduced | Supported |
|----------|--------------------------------|-----------|
| true     | v0.4.0                         | &#x2713;  |
| false    | v0.4.0                         | &#x2713;  |
| not      | v0.4.0                         | &#x2713;  |
| and      | v0.4.0                         | &#x2713;  |
| or       | v0.4.0                         | &#x2713;  |
| xor      | v0.4.0                         | &#x2713;  |


### Char
| Function      | Morphir-Elm Version Introduced | Supported |
|---------------|--------------------------------|-----------|
| isUpper       | v2.31.3                        | &#x2715;  |
| isLower       | v2.31.3                        | &#x2715;  | 
| isAlpha       | v2.31.3                        | &#x2715;  | 
| isAlphaNum    | v2.31.3                        | &#x2715;  | 
| isDigit       | v2.31.3                        | &#x2715;  |
| isOctDigit    | v2.31.3                        | &#x2715;  | 
| isHexDigit    | v2.31.3                        | &#x2715;  | 
| toUpper       | v2.31.3                        | &#x2715;  | 
| toLower       | v2.31.3                        | &#x2715;  | 
| toLocaleUpper | v2.31.3                        | &#x2715;  | 
| toLocaleLower | v2.31.3                        | &#x2715;  | 
| toCode        | v2.31.3                        | &#x2715;  | 
| fromCode      | v2.31.3                        | &#x2715;  | 

### Morphir.SDK.Decimal
| Function          | Morphir-Elm Version Introduced | Supported |
|-------------------|--------------------------------|-----------|
| fromInt           | v2.8.0                         | &#x2713;  |
| fromFloat         | v2.8.0                         | &#x2715;  |
| fromString        | v2.8.0                         | &#x2713;  |
| hundred           | v2.8.0                         | &#x2715;  |
| thousand          | v2.8.0                         | &#x2713;  |
| million           | v2.8.0                         | &#x2715;  |
| tenth             | v2.8.0                         | &#x2715;  |
| hundredth         | v2.8.0                         | &#x2715;  |
| thousandth        | v2.8.0                         | &#x2715;  |
| millionth         | v2.8.0                         | &#x2715;  |
| bps               | v2.8.0                         | &#x2713;  |
| toString          | v2.8.0                         | &#x2715;  |
| add               | v2.8.0                         | &#x2713;  |
| sub               | v2.8.0                         | &#x2713;  |
| negate            | v2.8.0                         | &#x2713;  |
| mul               | v2.8.0                         | &#x2713;  |
| div               | v2.12.0                        | &#x2713;  |
| divWithDefault    | v2.12.0                        | &#x2713;  |
| truncate          | v2.8.0                         | &#x2713;  |
| round             | v2.8.0                         | &#x2713;  |
| gt                | v2.8.0                         | &#x2713;  |
| gte               | v2.8.0                         | &#x2713;  |
| eq                | v2.8.0                         | &#x2713;  |
| neq               | v2.8.0                         | &#x2713;  |
| lt                | v2.8.0                         | &#x2713;  |
| lte               | v2.8.0                         | &#x2713;  |
| compare           | v2.8.0                         | &#x2713;  |
| abs               | v2.8.0                         | &#x2713;  |
| shiftDecimalLeft  | v2.12.0                        | &#x2715;  |
| shiftDecimalRight | v2.12.0                        | &#x2715;  |
| zero              | v2.8.0                         | &#x2713;  |
| one               | v2.8.0                         | &#x2713;  |
| minusOne          | v2.8.0                         | &#x2713;  |


### Morphir.SDK.Dict
#### Types

| Type | Morphir-Elm Version Introduced | Supported |
|------|--------------------------------|-----------|
| Dict | v1.0.0                         | &#x2713;  |

#### Functions

| Function  | Morphir-Elm Version Introduced | Supported |
|-----------|--------------------------------|-----------|
| empty     | v2.41.0                        | &#x2713;  |
| singleton | v2.41.0                        | &#x2713;  |
| insert    | v2.41.0                        | &#x2713;  |
| update    | v2.41.0                        | &#x2713;  |
| remove    | v2.41.0                        | &#x2713;  |
| isEmpty   | v2.41.0                        | &#x2713;  |
| member    | v2.41.0                        | &#x2713;  |
| get       | v2.41.0                        | &#x2713;  |
| size      | v2.41.0                        | &#x2713;  |
| keys      | v2.41.0                        | &#x2713;  |
| values    | v2.41.0                        | &#x2713;  |
| toList    | v2.41.0                        | &#x2713;  |
| fromList  | v2.41.0                        | &#x2713;  |
| map       | v2.41.0                        | &#x2715;  |
| foldl     | v2.41.0                        | &#x2715;  |
| foldr     | v2.41.0                        | &#x2715;  |
| filter    | v2.41.0                        | &#x2713;  |
| partition | v2.41.0                        | &#x2713;  |
| union     | v2.41.0                        | &#x2715;  |
| intersect | v2.41.0                        | &#x2715;  |
| diff      | v2.41.0                        | &#x2713;  |
| merge     | v2.41.0                        | &#x2713;  |

### Morphir.SDK.Float
#### Types

| Type    | Morphir-Elm Version Introduced | Supported |
|---------|--------------------------------|-----------|
| Float   | v0.4.0                         | &#x2713;  |
| Float32 | v0.4.0                         | &#x2713;  |
| Float64 | v0.4.0                         | &#x2713;  |

#### Functions

| Function   | Morphir-Elm Version Introduced | Supported |
|------------|--------------------------------|-----------|
| divide     | v0.4.0                         | &#x2713;  |
| fromInt    | v0.4.0                         | &#x2715;  |
| round      | v0.4.0                         | &#x2715;  |
| floor      | v0.4.0                         | &#x2715;  |
| ceiling    | v0.4.0                         | &#x2715;  |
| truncate   | v0.4.0                         | &#x2715;  |
| sqrt       | v0.4.0                         | &#x2715;  |
| logBase    | v0.4.0                         | &#x2713;  |
| e          | v0.4.0                         | &#x2713;  |
| pi         | v0.4.0                         | &#x2713;  |
| cos        | v0.4.0                         | &#x2715;  |
| sin        | v0.4.0                         | &#x2715;  |
| tan        | v0.4.0                         | &#x2715;  |
| acos       | v0.4.0                         | &#x2715;  |
| asin       | v0.4.0                         | &#x2715;  |
| atan       | v0.4.0                         | &#x2715;  |
| atan2      | v0.4.0                         | &#x2715;  |
| isNan      | v0.4.0                         | &#x2715;  |
| isInfinite | v0.4.0                         | &#x2715;  |
| degrees    | v2.0.0                         | &#x2715;  | 
