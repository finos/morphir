# Automating RegTech

There are a number of highly regulated industries that must adhere to complex regulations from various regulatory bodies.  These often come in the form of lengthy documents that can be arcane, ambiguous, and expensive to interpret into computer code.  It's even more expensive to adapt these regulations to a firm's internal systems.  There is no competitive advantage for firms in mastering these regulations separately, so it would be mutually beneficial to have a single shared model. The shared model could contain verification and comprehensive testing to ensure compliance.  

There have been attempts to do so by providing libraries.  The challenge with this approach is that these libraries don't work with firms' existing systems.  So in order to use them they would need to invest significantly in building new systems.

There is an alternative.  If regulations were codified in a declarative model that could be processed, like with Morphir, then that would enable firms to create processors to adapt the models into their own systems. In that way they get the advantage of a codified, unambiguous, and verifiable model while still retaining their existing systems.

# Use case: US LCR
The [US Liquidity Coverage Ratio](https://en.wikipedia.org/wiki/Basel_III#US_version_of_the_Basel_Liquidity_Coverage_Ratio_requirements) is a required report for certain banks and systemically important financial institutions.  It's definition can be found at [https://www.govinfo.gov/content/pkg/FR-2014-10-10/pdf/2014-22520.pdf](https://www.govinfo.gov/content/pkg/FR-2014-10-10/pdf/2014-22520.pdf).  It's complex enough that the there are accompanying documents and samples that attempt to clarify it.  Ultimately it's a set of calculations that can be defined concisely and unambiguously in a concise and unambiguous programming language.

We'll step through how we can define such a regulation using Morphir using the LCR as an example.

# Getting started
If you've not already done so, install Morphir as per the [getting started](./getting_started) instructions.  Create a project called "lcr":

```bash
morphir init lcr
cd lcr
```
In this example we'll use Elm as the Morphir modeling language.  If you've not done so, [install elm](https://guide.elm-lang.org/install/elm.html).

# Modeling the LCR
Let's define the core of the calculation for Morphir. The full LCR is quite extensive so we'll focus on a few examples that highlight different aspects of modeling.  

## Modeling calculations
At a high level, the LCR is a calculation.  In fact, if you look it up the first thing you'll run into is probably this calculation:
``` LCR = High quality liquid asset amount (HQLA) / Total net cash flow amount```
​
In modeling terms, it's not actually that simple since the LCR is calculated using a window from a given date.  It also needs to run on a set of data.  So in our model we'll define it as a function:

```elm
lcr toCounterparty product t flowsForDate reserveBalanceRequirement = 
    let
        hqla                = hqlaAmount product (flowsForDate t) reserveBalanceRequirement
        totalNetCashOutflow = totalNetCashOutflowAmount toCounterparty t flowsForDate
    in
        hqla / totalNetCashOutflow
```

As you can see, that's pretty expressive and the last line matches the calculation.  For anyone new to Elm, the first line declares the function. Elm uses spaces rather than (,) to itemize parameters.  You might be wondering what some of these extra parameters are all about. These are the points where the logical model meets the physical context that it will be run in.  They are parameters at the top level so that individual firms can specify them as needed.  The parameter named ```product``` is a good example.  It's a function that takes a product key and returns the product structure.  It's up to the model user to determine how product identification and lookup will be supplied by their system.

If you read the specification, you'll see a fair amount of space used to describe something called the adjusted excess HQLA amount.  This happens to be a nice calculation to demonstrate mathematical modeling:

```elm
adjustedExcessHQLAAmount = 
    let
        adjustedLevel1LiquidAssetAmount = level1LiquidAssetAmount

        adjustedlevel2aLiquidAssetAmount = level2aLiquidAssetAmount * 0.85

        adjustedlevel2bLiquidAssetAmount = level2bLiquidAssetAmount * 0.50

        adjustedLevel2CapExcessAmount = 
            max (adjustedlevel2aLiquidAssetAmount + adjustedlevel2bLiquidAssetAmount - 0.6667 * adjustedLevel1LiquidAssetAmount) 0.0

        adjustedlevel2bCapExcessAmount =
            max (adjustedlevel2bLiquidAssetAmount - adjustedLevel2CapExcessAmount - 0.1765 * (adjustedLevel1LiquidAssetAmount + adjustedlevel2aLiquidAssetAmount)) 0.0
    in
        adjustedLevel2CapExcessAmount + adjustedlevel2bCapExcessAmount
```

It's included here just to show how much easier it is to understand a model than the written descritpion [TODO: cite the text].

## Modeling collection operations
The LCR spec is peppered with operations of collections of data.  For example:

```elm
level2aLiquidAssetsThatAreEligibleHQLA =
    t0Flows
        |> List.filter (\flow -> flow.assetType == Level2aAssets && isHQLA product flow)
        |> List.map .amount
        |> List.sum
```

It's pretty easy to see that this takes a collection, filters it, then sums the "amount" of the remaining.  The important point to note here is that we're letting the model know of a collection while also leaving the implementation entirely undefined.  This allows us to process this model into a variety of execution contexts.  For example the above model could be translated to:

**SQL**
```sql
select sum amount
from t0_flows tf
where tf.assetType = 'Level 2a Assets' and tf.isHQLA = 'T'
```

**Spark Scala**
```scala
t0Flows
    .filter {flow => flow.assetType == Level2aAssets && isHQLA(product, flow)}
    .map (_.amount)
    .sum
```

You can see in the examples that the generated code makes some assumptions about the physical environment.  These are the things that are likely to be very different across firms.  The value of modeling is that each firm can customize the code generation to match their own environments.

## Modeling structures
The previous example contained a collection name t0Flows.  We can see from the example that it has  assetType and amount fields.  In fact, this is defined in the spec as a cash flow, which contains a few other fields.  At this point in our modeling, we have a couple of options.  We can either use a single common structure throughout the model, even when large portions of the app don't require all of those fields or we can create multiple structures that are more aligned with the usage.  Since the LCR actually defines a cash flow, we'll go with the first option since it matches the language of the business.  The cash flow is defined as:

```elm
type alias BusinessDate = Date


type alias ReportingEntity = Entity


type alias Flow =
    { amount : Amount
    , assetType : AssetCategoryCodes
    , businessDate : BusinessDate
    , collateralClass : AssetCategoryCodes
    , counterpartyId : CounterpartyId
    , currency : Currency
    , fed5GCode : Fed5GCode
    , insured : InsuranceType
    , isTreasuryControl : Bool
    , isUnencumbered : Bool
    , maturityDate : BusinessDate
    , effectiveMaturityDate : BusinessDate
    , productId : ProductId
    }
```

Notice that most of the types are named using the language of the business.  This is a aspect of domain modeling, the ubiquitous language, that helps all of the stakeholders to reduce misunderstandings.

# Verifying the model
This is just a small sampling of what's required to turn a full specification into functioning code. It's enough to see that it's not a trivial task and there's a significant advantage if someone else could do it for you *and* prove that it's correct.  This is where the use of a pure functional programming language for business modeling really shines.  The common statement that *"if it compiles it's guaranteed to run without errors"* really applies well to RegTech.  The Elm compiler catches a huge number of potential errors that would otherwise be possible in non-FP languages.  

It's worth noting that there are languages that provide even more guarantees, like Coq and Microsoft's Bosque.  In creating Morphir, we were careful not to write our own or lockin on a particular language.  This leaves the possibility to use the best language for the job as long as that language can be co-compiled into the Morphir IR.

[TODO] show examples of catching errors

# Using automation to adapt the model to your systems
