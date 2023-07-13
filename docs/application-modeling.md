---
id: modeling-entire-application
title: Modeling Entire Application
---

# Modeling Entire Applications

Morphir Application Modeling imagines an evolution of programming as:

- You code, just pure business logic.
- That code is guaranteed to be free of exceptions.
- Merging your code triggers full SDLC automation through to deployment.
- Your application automatically conforms to your firm's standards now and in the future.
- Your users have transparency into how your application behaves and why.
- You retain full control to modify any of the above.

Most applications generally follow a small set of well known patterns based on how the application will run
(as opposed to its business purpose). These patterns are what many application frameworks are built around. As a
result, much of the development process is simply following recipes to build code to these patterns.

There is another set of patterns that sits in the fuzzy area where the business patterns meet the technical ones. These
patterns are not entirely business and are consistent across applications regardless of how they will end up being
executed. It's likely that these patterns will remain unchanged even as technology evolves. If we can capture these
patterns in our models, it would allow us to move execution across different technologies without changing our models
at all. This is important because an individual application usually exists within a larger ecosystem. Constantly
keeping large numbers of existing applications up-to-date with the latest ecosystem changes, commonly referred to as
_hygiene_, takes a lot of development effort that subtracts from a team's ability to provide business value.

So what are these patterns? Here are some core patterns that drive a vast subset of applications:

- **API** - The combination of inputs and outputs that external applications use to interact with the application.
- **Local State** - The information owned and managed by the application.
- **Remote State** - Any information that is required by this application but not managed by it.

These are the core building blocks of many applications and can be implemented in a variety of technologies.

Let's look at an example. We'll use Morphir's Elm modeling support, so
[follow the installation instructions](https://github.com/Morgan-Stanley/morphir-elm#installation-1) to get started.

## Application Overview

For this example, we'll look at a set of interacting applications that form a complete order processing system. They include:

- [Books and Records](https://github.com/Morgan-Stanley/morphir-examples/tree/master/src/Morphir/Sample/Apps/BooksAndRecords) - Keeps
  the books on what orders have been executed.
- [Order](https://github.com/Morgan-Stanley/morphir-examples/tree/master/src/Morphir/Sample/Apps/Order) - Processes
  order requests and records any confirmations to Books and Records.
- [Trader](https://github.com/Morgan-Stanley/morphir-examples/tree/master/src/Morphir/Sample/Apps/Trader) - An automated
  trading algorithm that makes decisions based on the market and the state of the current book of deals. It
  relies on Books, Records, and Order.

## Modeling the Persistent App specification

All three of these are instances of applications that manage:

## Modeling the API

Books and Records is used by Order to book executions, so it needs a way to accept orders. We model this in Morphir
using the API type as such:

```elm
type alias API =
    { openDeal : ID -> Product.ID -> Price -> Quantity -> Result OpenRequestFault Event
    , closeDeal : ID -> Result CloseRequestFault Event
    }
```

This states that Books and Records exposes an endpoint to open a deal and another to close an existing deal. In each
case, the outcome of the request is communicated by an event that either confirms or gives a message about why the
request was rejected. Note that it doesn't state whether these calls are synchronous or asynchronous. That's because
that decision is an infrastructure ecosystem concern, not a business concern. That means we should save the decision to
a later stage when we decide how the application fits into the ecosystem. If we decide now, we're locking ourselves to
one execution paradigm before we have enough information.

We know that other applications will be interested in knowing what's happening in Books and Records even if they're not
making requests. So we declare that Books and Records publishes events about what's going on:

```elm
type Event
    = DealOpened ID Product.ID Price Quantity
    | DealClosed ID
```

## Modeling the Local State

Books and Records by definition owns the state required for book management. We want to declare what state is owned so
that we can plug it into our persistence ecosystem eventually. We do this with:

```elm
type alias LocalState =
    Dict ID Deal
```

## Modeling Remote State Dependencies

Some applications need information managed outside their domain. The Order application demonstrates this. It declares
these external dependencies using the RemoteState type:

```elm
type alias RemoteState =
    { bookBuy : Order.ID -> Product.ID -> Price -> Int -> Cmd Event
    , bookSell : Order.ID -> Price -> Cmd Event
    , getDeal : Order.ID -> Maybe Deal.Deal
    , getMarketPrice : Product.ID -> Maybe Price
    , getStartOfDayPosition : Product.ID -> Maybe Quantity
    }
```

Here we state that Order depends on the ability to book order executions, to look up the current state of a deal,
to get the current market price for a product, and to get the product's inventory. It needs all of this information to
make decisions. Notice that it doesn't specify what's going to satisfy these dependencies. That's an infrastructure
ecosystem decision based on knowledge that we don't have as modellers.

## The Full Models

These three patterns cover most applications. For the full example models take a look at
[the Morphir examples project](https://github.com/Morgan-Stanley/morphir-examples/tree/master/src/Morphir/Sample/Apps).

# Execution

There are many ways that we can run these applications. The advantage of modeling them is that we can choose and
customize as needed without rewriting any of our core business concepts. For this example, we will take advantage of
the fact that Microsoft has recognized this very set of patterns in its cloud-ready [Dapr Platform](http://dapr.io). Each
of our modeled patterns has a corresponding Dapr feature that we can take advantage of.

Our model patterns map to Dapr in the following ways:

- **API Requests** - Our API requests turn into REST services defined by generating OpenAPI specifications. Alternatively,
  we could choose to use a message queue or Kafka for asynchronous requests.
- **API Events** - Events are published to Kafka as event logs.
- **Local State** - Dapr supports Redis natively, so we'll use that for persistence.
- **Remote State** - Given that we've made the REST decision, all the external applications will also be exposed that
  way. These will turn into REST calls and get bound to the owning applications during the SDLC pipeline.

For more information on Morphir's Dapr support, take a look at the [morphir-dapr](https://github.com/Morgan-Stanley/morphir-dapr) project.

# SDLC Pipeline

We can utilize various SDLC technologies to create straight-through deployment. In this example, we'll utilize GitHub's
pipeline technology to trigger a full deployment lifecycle every time we make a change to the model.

# Summing Up

In this example we've created a full set of distributed applications using Morphir, and we've managed to do so without
writing a single bit of non-business code. The cool part is that it doesn't mean that we're locked into a particular
platform or vendor. We can always change the execution target by using another Morphir backend or writing our own.

We've also demonstrated a true front-to-back SDLC pipeline that automates full deployment from the moment you check in your model.

The end result is an application development that finally **lets developers focus solely on providing business value
without sacrificing technical flexibility**. That should be pretty compelling to anyone who's struggled to balance
providing business value against all the cursory development tasks.

[Home](/index) | [Posts](posts) | [Examples](https://github.com/finos/morphir-examples/)
