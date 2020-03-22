# What makes a good domain model?

We all strive to build high-quality software and that begins with a clean and well-defined domain model. But what do we mean when we say 
"clean" or "well-defined"? Without specific measures it is difficult to agree whether a change in the domain model makes it better or worse
which stands in the way of continuous improvement. In this post we'll dive into how we can measure and improve the quality of our domain 
models.

Let's start by differentiating two important aspects of quality:

- Exactness
  - Making invalid state unrepresentable is a well-known principle in the functional-programming community which refers to avoiding 
  ambiguity that leaves the model open to interpretation.
  - A simple example of this is when a model uses strings instead of enums. Strings are ambiguous because they leave the interpretation
  to the consumer completely while enums limit the possible values significantly.
  - This aspect is relatively easy to measure and we will list out some specific metrics we can use.
- Alignment
  - A domain model serves a very specific purpose: IT DESCRIBES A BUSINESS PROBLEM ...

## Exactness

## Alignment
