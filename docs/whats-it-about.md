---
id: what-is-it-about
title: I Have an Application
---

# I Have an Application

- It tracks product inventories and decides how much to grant an order request based on the product's availability.
- It is deployed as a set of microservices.
  - We're thinking about moving the microservices to serverless.
- Orders are made via REST.
  - The REST is exposed via OpenAPI.
- Inventory levels are tracked in real-time with stream processing and come from a variety of sources.
  - We currently use Kafka for streaming.
  - Some sources contain nuances about how to interpret their contents into trustworthy inventory numbers.
  - There are also rules for how to distribute inventory across requests to try to get a good balance of happy customers.
- We use a standard SQL database for transaction processing.

# What's important?

As you're reading this, what do you consider to be the most important information in my description? Is it the Kafka
stream processing? The standard microservices architecture? Or the fact that we're thinking of moving to serverless?
While the answer might be subjective, I can tell you that, for the users of this application, the most important parts are:

1. The application processes orders for products.
1. It allocates to those orders based on availability and distribution rules.
1. It aggregates inventory from multiple suppliers.

# Morphir

You probably know these as the application's business logic, and it's easy to see why users think this is most
important: it is the whole reason the application exists at all. Everything else is temporary details about how it's implemented. Chances are that these details will change a few times over the application's lifetime. It would be a shame to risk breaking the most important parts of the application just because we want to change from microservices to serverless, yet that's exactly what happens with a huge portion of applications. We want something that allows the business and technology to evolve independently. This is what Morphir does; it's all about the business concepts.

# Working Across Technologies

Most applications mix the business concepts with the technology choices of the moment. Given the importance of the
business concepts, it makes sense to protect them from transient technical decisions as much as possible.

For starters, you definitely want it to perform correctly, ideally across different technologies and
platforms. Finding yourself constantly rewriting your API? Technology is advancing quickly; you certainly don't want
your API locked in legacy technology.

[Home](/index) | [Posts](posts) | [Examples](https://github.com/finos/morphir-examples/)
