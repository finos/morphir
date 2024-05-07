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
| greaterThan        | v2.0.0                         | &#x2713;  |
| lessThanOrEqual    | v2.0.0                         | &#x2713;  |
| greaterThanOrEqual | v2.0.0                         | &#x2713;  |
| max                | v2.0.0                         | &#x2713;  |
| min                | v2.0.0                         | &#x2713;  |
| compare            | v2.0.0                         | &#x2713;  |

#### Float
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| divide             | v0.4.0                         | &#x2713;  |
| round              | v0.4.0                         | &#x2715;  |
| floor              | v0.4.0                         | &#x2715;  |
| ceiling            | v0.4.0                         | &#x2715;  |
| truncate           | v0.4.0                         | &#x2715;  |
| isNan              | v0.4.0                         | &#x2713;  |
| isInfinite         | v0.4.0                         | &#x2713;  |
| e                  | v0.4.0                         | &#x2713;  |
| pi                 | v0.4.0                         | &#x2713;  |
| cos                | v0.4.0                         | &#x2713;  |
| sin                | v0.4.0                         | &#x2713;  |
| tan                | v0.4.0                         | &#x2713;  |
| acos               | v0.4.0                         | &#x2713;  |
| asin               | v0.4.0                         | &#x2713;  |
| atan               | v0.4.0                         | &#x2713;  |
| atan2              | v0.4.0                         | &#x2713;  |
| degrees            | v2.0.0                         | &#x2713;  | 
| radians            | v2.0.0                         | &#x2713;  | 
| turns              | v2.0.0                         | &#x2713;  | 
| toPolar            | v2.0.0                         | &#x2715;  | 
| fromPolar          | v2.0.0                         | &#x2715;  | 
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2713;  |
| lessThanOrEqual    | v2.0.0                         | &#x2713;  |
| greaterThanOrEqual | v2.0.0                         | &#x2713;  |
| max                | v2.0.0                         | &#x2713;  |
| min                | v2.0.0                         | &#x2713;  |
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
| max                | v2.0.0                         | &#x2713;  |
| min                | v2.0.0                         | &#x2713;  |
| compare            | v2.0.0                         | &#x2713;  |

#### List
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| append             | v2.0.0                         | &#x2713;  |
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2713;  |
| lessThanOrEqual    | v2.0.0                         | &#x2713;  |
| greaterThanOrEqual | v2.0.0                         | &#x2713;  |
| max                | v2.0.0                         | &#x2713;  |
| min                | v2.0.0                         | &#x2713;  |
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
| greaterThan        | v2.0.0                         | &#x2713;  |
| lessThanOrEqual    | v2.0.0                         | &#x2713;  |
| greaterThanOrEqual | v2.0.0                         | &#x2713;  |
| max                | v2.0.0                         | &#x2713;  |
| min                | v2.0.0                         | &#x2713;  |
| compare            | v2.0.0                         | &#x2713;  |

#### Tuple
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2713;  |
| lessThanOrEqual    | v2.0.0                         | &#x2713;  |
| greaterThanOrEqual | v2.0.0                         | &#x2713;  |
| max                | v2.0.0                         | &#x2713;  |
| min                | v2.0.0                         | &#x2713;  |
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
| isUpper       | v2.31.3                        | &#x2713;  |
| isLower       | v2.31.3                        | &#x2713;  | 
| isAlpha       | v2.31.3                        | &#x2713;  | 
| isAlphaNum    | v2.31.3                        | &#x2713;  | 
| isDigit       | v2.31.3                        | &#x2713;  |
| isOctDigit    | v2.31.3                        | &#x2713;  | 
| isHexDigit    | v2.31.3                        | &#x2713;  | 
| toUpper       | v2.31.3                        | &#x2713;  | 
| toLower       | v2.31.3                        | &#x2713;  | 
| toLocaleUpper | v2.31.3                        | &#x2713;  | 
| toLocaleLower | v2.31.3                        | &#x2713;  | 
| toCode        | v2.31.3                        | &#x2713;  | 
| fromCode      | v2.31.3                        | &#x2713;  | 

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
| shiftDecimalLeft  | v2.12.0                        | &#x2713;  |
| shiftDecimalRight | v2.12.0                        | &#x2713;  |
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
| map       | v2.41.0                        | &#x2713;  |
| foldl     | v2.41.0                        | &#x2713;  |
| foldr     | v2.41.0                        | &#x2713;  |
| filter    | v2.41.0                        | &#x2713;  |
| partition | v2.41.0                        | &#x2713;  |
| union     | v2.41.0                        | &#x2713;  |
| intersect | v2.41.0                        | &#x2713;  |
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
| cos        | v0.4.0                         | &#x2713;  |
| sin        | v0.4.0                         | &#x2713;  |
| tan        | v0.4.0                         | &#x2713;  |
| acos       | v0.4.0                         | &#x2713;  |
| asin       | v0.4.0                         | &#x2713;  |
| atan       | v0.4.0                         | &#x2713;  |
| atan2      | v0.4.0                         | &#x2713;  |
| isNan      | v0.4.0                         | &#x2713;  |
| isInfinite | v0.4.0                         | &#x2713;  |
| degrees    | v2.0.0                         | &#x2713;  | 
| radians    | v2.0.0                         | &#x2713;  | 
| turns      | v2.0.0                         | &#x2713;  | 
| toPolar    | v2.0.0                         | &#x2715;  | 
| fromPolar  | v2.0.0                         | &#x2715;  | 



### Morphir.SDK.Int
#### Types

| Type   | Morphir-Elm Version Introduced | Supported |
|--------|--------------------------------|-----------|
| Int    | v0.4.0                         | &#x2713;  |
| Int8   | v0.4.0                         | &#x2713;  |
| Int16  | v0.4.0                         | &#x2713;  |
| Int32  | v0.4.0                         | &#x2713;  |
| Int64  | v0.4.0                         | &#x2713;  |

#### Functions

| Function    | Morphir-Elm Version Introduced | Supported |
|-------------|--------------------------------|-----------|
| fromInt8    | v2.9.0                         | &#x2715;  | 
| toInt8      | v2.9.0                         | &#x2715;  | 
| fromInt16   | v2.9.0                         | &#x2715;  |
| toInt16     | v2.9.0                         | &#x2715;  | 
| fromInt32   | v2.9.0                         | &#x2715;  |
| toInt32     | v2.9.0                         | &#x2715;  | 
| fromInt64   | v2.9.0                         | &#x2715;  | 
| toInt64     | v2.9.0                         | &#x2715;  | 


### Morphir.SDK.Key
| Function | Morphir-Elm Version Introduced | Supported  |
|----------|--------------------------------|------------|
| noKey    | v0.7.0                         | &#x2715;   |
| key0     | v0.7.0                         | &#x2715;   |
| key2     | v0.7.0                         | &#x2715;   |
| key3     | v0.7.0                         | &#x2715;   |
| key4     | v0.7.0                         | &#x2715;   |
| key5     | v0.7.0                         | &#x2715;   |
| key6     | v0.7.0                         | &#x2715;   |
| key7     | v0.7.0                         | &#x2715;   |
| key8     | v0.7.0                         | &#x2715;   |
| key9     | v0.7.0                         | &#x2715;   |
| key10    | v0.7.0                         | &#x2715;   |
| key11    | v0.7.0                         | &#x2715;   |
| key12    | v0.7.0                         | &#x2715;   |
| key13    | v0.7.0                         | &#x2715;   |
| key14    | v0.7.0                         | &#x2715;   |
| key15    | v0.7.0                         | &#x2715;   |
| key16    | v0.7.0                         | &#x2715;   |

### Morphir.SDK.List
| Function    | Morphir-Elm Version Introduced | Supported |
|-------------|--------------------------------|-----------|
| singleton   | v2.0.0                         | &#x2713;  |
| repeat      | v2.0.0                         | &#x2713;  |
| range       | v2.0.0                         | &#x2713;  |
| cons        | v2.0.0                         | &#x2715;  |
| map         | v2.0.0                         | &#x2713;  |
| indexedMap  | v2.0.0                         | &#x2713;  |
| foldl       | v2.0.0                         | &#x2713;  |
| foldr       | v2.0.0                         | &#x2713;  |
| filter      | v2.0.0                         | &#x2713;  |
| filterMap   | v2.0.0                         | &#x2713;  |
| length      | v2.0.0                         | &#x2713;  |
| reverse     | v2.0.0                         | &#x2713;  |
| member      | v2.0.0                         | &#x2713;  |
| all         | v2.0.0                         | &#x2713;  |
| any         | v2.0.0                         | &#x2713;  |
| maximum     | v2.0.0                         | &#x2713;  |
| minimum     | v2.0.0                         | &#x2713;  |
| sum         | v2.0.0                         | &#x2715;  |
| product     | v2.0.0                         | &#x2715;  |
| append      | v2.0.0                         | &#x2713;  |
| concat      | v2.0.0                         | &#x2713;  |
| concatMap   | v2.0.0                         | &#x2713;  |
| intersperse | v2.0.0                         | &#x2715;  |
| map2        | v2.0.0                         | &#x2715;  |
| map3        | v2.0.0                         | &#x2715;  |
| map4        | v2.0.0                         | &#x2715;  |
| map5        | v2.0.0                         | &#x2715;  |
| sort        | v2.0.0                         | &#x2713;  |
| sortBy      | v2.0.0                         | &#x2713;  |
| sortWith    | v2.0.0                         | &#x2713;  |
| isEmpty     | v2.0.0                         | &#x2713;  |
| head        | v2.0.0                         | &#x2713;  |
| tail        | v2.0.0                         | &#x2713;  |
| take        | v2.0.0                         | &#x2713;  |
| drop        | v2.0.0                         | &#x2713;  |
| partition   | v2.0.0                         | &#x2713;  |
| unzip       | v2.0.0                         | &#x2715;  |
| innerJoin   | v2.0.0                         | &#x2715;  |
| leftJoin    | v2.0.0                         | &#x2715;  |

### Morphir.SDK.LocalDate
#### Types

| Function  | Morphir-Elm Version Introduced | Supported |
|-----------|--------------------------------|-----------|
| LocalDate | v1.5.0                         | &#x2713;  |
| DayOfWeek | v2.84.2                        | &#x2713;  |
| Month     | v2.84.2                        | &#x2713;  |

#### Functions

| Function         | Morphir-Elm Version Introduced | Supported |
|------------------|--------------------------------|-----------|
| diffInDays       | v1.5.0                         | &#x2713;  |
| diffInWeeks      | v1.5.0                         | &#x2713;  |
| diffInMonths     | v1.5.0                         | &#x2713;  |
| diffInYears      | v1.5.0                         | &#x2713;  |
| addDays          | v1.5.0                         | &#x2713;  |
| addWeeks         | v1.5.0                         | &#x2713;  |
| addMonths        | v1.5.0                         | &#x2713;  |
| addYears         | v1.5.0                         | &#x2713;  |
| fromCalendarDate | v2.87.0                        | &#x2713;  |
| fromISO          | v2.4.0                         | &#x2713;  |
| fromOrdinalDate  | v2.87.0                        | &#x2713;  |
| fromParts        | v2.4.0                         | &#x2713;  |
| toISOString      | v2.66.0                        | &#x2713;  |
| monthToInt       | v2.87.0                        | &#x2713;  |
| dayOfWeek        | v2.84.2                        | &#x2713;  |
| isWeekend        | v2.84.2                        | &#x2713;  |
| isWeekday        | v2.84.2                        | &#x2713;  |
| year             | v2.84.2                        | &#x2713;  |
| month            | v2.84.2                        | &#x2713;  |
| monthNumber      | v2.87.0                        | &#x2713;  |
| day              | v2.84.2                        | &#x2713;  |


### Morphir.SDK.LocalTime
#### Types

| Function  | Morphir-Elm Version Introduced | Supported |
|-----------|--------------------------------|-----------|
| LocalTime | v2.44.0                        | &#x2713;  |

#### Functions

| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| fromMilliseconds   | v2.44.0                        | &#x2713;  |
| addHours           | v2.44.0                        | &#x2713;  |
| addMinutes         | v2.44.0                        | &#x2713;  |
| addSeconds         | v2.44.0                        | &#x2713;  |
| diffInHours        | v2.44.0                        | &#x2713;  |
| diffInMinutes      | v2.44.0                        | &#x2713;  | 
| diffInSeconds      | v2.44.0                        | &#x2713;  |
| fromISO            | v2.44.0                        | &#x2713;  |


### Morphir.SDK.Maybe
| Function    | Morphir-Elm Version Introduced | Supported |
|-------------|--------------------------------|-----------|
| withDefault | v2.84.2                        | &#x2713;  |
| map         | v2.84.2                        | &#x2713;  |
| map2        | v2.84.2                        | &#x2713;  |
| map3        | v2.84.2                        | &#x2713;  |
| map4        | v2.84.2                        | &#x2713;  |
| andThen     | v2.84.2                        | &#x2713;  |
| hasValue    | v2.84.2                        | &#x2713;  |


### Morphir.SDK.Number
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| fromInt            | v2.10.0                        | &#x2715;  |
| equal              | v2.10.0                        | &#x2715;  |
| notEqual           | v2.10.0                        | &#x2715;  |
| lessThan           | v2.11.0                        | &#x2715;  |
| lessThanOrEqual    | v2.11.0                        | &#x2715;  |
| greaterThan        | v2.11.0                        | &#x2715;  |
| greaterThanOrEqual | v2.11.0                        | &#x2715;  |
| add                | v2.10.0                        | &#x2715;  |
| subtract           | v2.11.0                        | &#x2715;  |
| multiply           | v2.11.0                        | &#x2715;  |
| divide             | v2.10.0                        | &#x2715;  |
| abs                | v2.11.0                        | &#x2715;  |
| negate             | v2.11.0                        | &#x2715;  |
| reciprocal         | v2.11.0                        | &#x2715;  |
| toFractionalString | v2.11.0                        | &#x2715;  |
| toDecimal          | v2.11.0                        | &#x2715;  |
| coerceToDecimal    | v2.12.0                        | &#x2715;  |
| simplify           | v2.11.0                        | &#x2715;  |
| isSimplified       | v2.11.0                        | &#x2715;  |
| zero               | v2.10.0                        | &#x2715;  |
| one                | v2.11.0                        | &#x2715;  |


### Regex
| Function       | Morphir-Elm Version Introduced | Supported |
|----------------|--------------------------------|-----------|
| fromString     | v2.81.0                        | &#x2715;  |
| fromStringWith | v2.81.0                        | &#x2715;  |
| never          | v2.81.0                        | &#x2715;  |
| contains       | v2.81.0                        | &#x2715;  |
| split          | v2.81.0                        | &#x2715;  |
| find           | v2.81.0                        | &#x2715;  |
| replace        | v2.81.0                        | &#x2715;  |
| splitAtMost    | v2.81.0                        | &#x2715;  |
| findAtMost     | v2.81.0               -        | &#x2715;  |
| replaceAtMost  | v2.81.0                        | &#x2715;  |

### Result
| Function    | Morphir-Elm Version Introduced | Supported |
|-------------|--------------------------------|-----------|
| andThen     | v2.0.0                         | &#x2713;  |
| map         | v2.0.0                         | &#x2713;  |
| map2        | v2.0.0                         | &#x2715;  |
| map3        | v2.0.0                         | &#x2715;  |
| map4        | v2.0.0                         | &#x2715;  |
| map5        | v2.0.0                         | &#x2715;  |
| withDefault | v2.0.0                         | &#x2713;  |
| toMaybe     | v2.0.0                         | &#x2713;  |
| fromMaybe   | v2.0.0                         | &#x2713;  |
| mapError    | v2.0.0                         | &#x2713;  |


### Morphir.SDK.ResultList
| Function       | Morphir-Elm Version Introduced | Supported |
|----------------|--------------------------------|-----------|
| fromList       | v2.41.0                        | &#x2715;  |
| filter         | v2.41.0                        | &#x2715;  |
| filterOrFail   | v2.41.0                        | &#x2715;  |
| map            | v2.41.0                        | &#x2715;  |
| mapOrFail      | v2.41.0                        | &#x2715;  |
| errors         | v2.41.0                        | &#x2715;  |
| successes      | v2.41.0                        | &#x2715;  |
| partition      | v2.41.0                        | &#x2715;  |
| keepAllErrors  | v2.41.1                        | &#x2715;  |
| keepFirstError | v2.41.1                        | &#x2715;  |


### Morphir.SDK.Rule
| Function | Morphir-Elm Version Introduced | Supported |
|----------|--------------------------------|-----------|
| fromList | v0.7.0                         | &#x2715;  |
| chain    | v0.7.0                         | &#x2715;  |
| any      | v0.7.0                         | &#x2715;  |
| is       | v0.7.0                         | &#x2715;  |
| anyOf    | v0.7.0                         | &#x2715;  |
| noneOf   | v0.7.0                         | &#x2715;  |


### Set
| Function  | Morphir-Elm Version Introduced | Supported |
|-----------|--------------------------------|-----------|
| empty     | v2.2.0                         | &#x2713;  |
| singleton | v2.2.0                         | &#x2713;  |
| insert    | v2.2.0                         | &#x2713;  |
| remove    | v2.2.0                         | &#x2713;  |
| isEmpty   | v2.2.0                         | &#x2713;  |
| member    | v2.2.0                         | &#x2713;  |
| size      | v2.2.0                         | &#x2713;  |
| toList    | v2.2.0                         | &#x2713;  |
| fromList  | v2.2.0                         | &#x2713;  |
| map       | v2.2.0                         | &#x2713;  |
| foldl     | v2.2.0                         | &#x2713;  |
| foldr     | v2.2.0                         | &#x2713;  |
| filter    | v2.2.0                         | &#x2713;  |
| partition | v2.2.0                         | &#x2713;  |
| union     | v2.2.0                         | &#x2713;  |
| intersect | v2.2.0                         | &#x2713;  |
| diff      | v2.2.0                         | &#x2713;  |


### Morphir.SDK.StatefulApp
| Type        | Morphir-Elm Version Introduced | Supported |
|-------------|--------------------------------|-----------|
| StatefulApp | v1.1.0                         | &#x2715;  |


### Morphir.SDK.String
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| ofLength           | v1.4.0                         | &#x2713;  |
| ofMaxLength        | v1.4.0                         | &#x2713;  |
| equalIgnoreCase    | v1.4.0                         | &#x2713;  |
| isEmpty            | v2.0.0                         | &#x2713;  |
| length             | v2.0.0                         | &#x2713;  |
| reverse            | v2.0.0                         | &#x2713;  |
| repeat             | v2.0.0                         | &#x2713;  |
| replace            | v2.0.0                         | &#x2713;  |
| append             | v2.0.0                         | &#x2713;  |
| concat             | v2.0.0                         | &#x2713;  |
| split              | v2.0.0                         | &#x2713;  |
| join               | v2.0.0                         | &#x2713;  |
| words              | v2.0.0                         | &#x2713;  |
| lines              | v2.0.0                         | &#x2713;  |
| slice              | v2.0.0                         | &#x2713;  |
| left               | v2.0.0                         | &#x2713;  |
| right              | v2.0.0                         | &#x2713;  |
| dropLeft           | v2.0.0                         | &#x2713;  |
| dropRight          | v2.0.0                         | &#x2713;  |
| contains           | v2.0.0                         | &#x2713;  |
| startsWith         | v2.0.0                         | &#x2713;  |
| endsWith           | v2.0.0                         | &#x2713;  |
| indexes            | v2.0.0                         | &#x2713;  |
| indices            | v2.0.0                         | &#x2713;  |
| toInt              | v2.0.0                         | &#x2713;  |
| fromInt            | v2.0.0                         | &#x2713;  |
| toFloat            | v2.0.0                         | &#x2713;  |
| fromFloat          | v2.0.0                         | &#x2713;  |
| fromChar           | v2.0.0                         | &#x2713;  |
| cons               | v2.0.0                         | &#x2713;  |
| uncons             | v2.0.0                         | &#x2713;  |
| toList             | v2.0.0                         | &#x2713;  |
| fromList           | v2.0.0                         | &#x2713;  |
| toUpper            | v2.0.0                         | &#x2713;  |
| toLower            | v2.0.0                         | &#x2713;  |
| pad                | v2.0.0                         | &#x2713;  |
| padLeft            | v2.0.0                         | &#x2713;  |
| padRight           | v2.0.0                         | &#x2713;  |
| trim               | v2.0.0                         | &#x2713;  |
| trimLeft           | v2.0.0                         | &#x2713;  |
| trimRight          | v2.0.0                         | &#x2713;  |
| map                | v2.0.0                         | &#x2713;  |
| filter             | v2.0.0                         | &#x2713;  |
| foldl              | v2.0.0                         | &#x2713;  |
| foldr              | v2.0.0                         | &#x2713;  |
| any                | v2.0.0                         | &#x2713;  |
| all                | v2.0.0                         | &#x2713;  |


### Morphir.SDK.Validate
| Function        | Morphir-Elm Version Introduced | Supported |
|-----------------|--------------------------------|-----------|
| required        | v2.41.1                        | &#x2715;  |
| parse           | v2.41.1                        | &#x2715;  |
