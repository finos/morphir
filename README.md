# Morphir

Morphir is a **data format** that goes beyond just data and **captures business logic** as well. 
Turning business logic into data allows you to do more than just running it:

- You can **transform it** to move between languages and platforms effortlessly as technology evolves.
- You can **visualize it** to turn black-box logic into insightful explanations for your business users.
- You can **store it** to retrieve earlier versions of the logic in seconds to understand why the sytem made a decision 5 years ago.
- And much more ...

This probably sounds very abstract so here are a few specific topics if you are interested to learn more:

## Can I capture all my business logic?



## How does it turn logic into data?

The process of turning logic into data is well known because every programming language compiler and interpreter does it. They parse the source code to generate an [abstract syntax tree](https://en.wikipedia.org/wiki/Abstract_syntax_tree) which is then transformed into an [intermediate representation](https://en.wikipedia.org/wiki/Intermediate_representation) of some sort.

Morphir simply turns that intermediate representation into a developer-friendly data format that makes it easy to build automation on top of it.

## What does the data format look like?

```javascript
a + b
```

```javascript
["Apply"
, ["Apply"
  , ["Reference", [["Morphir", "SDK"], ["Number"], "add"]]
  , ["Variable", ["a"]]]
, ["Variable", ["b"]]
]
```

See more at our [Documentation](https://morgan-stanley.github.io/morphir/).
