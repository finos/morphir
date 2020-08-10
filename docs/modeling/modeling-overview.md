# What Does Using Morphir Entail?

So, you're thinking about using Morphir for your project. What does that mean exactly and what are you in for if you do?

## How using Morphir is different?

Morphir embraces the Functional Domain Modeling (FDM) approach to development.  FDM's emphasis is on capturing the business concepts and then projecting them into various runtime contexts.  In practice, this means that we approach development in a different way than is often done. It's more of a formalized Hexogonal Architecture approach.

## Modeling 

One of the main pillars of FDM is that modeling the business is a unique discipline that must be approached independent from the technology.  What this means in Morphir is that you'll start with the models and work them out before ever getting into the technology needed to execute them.  We currently do this modeling in the Elm programming langauge.  As a general rule, we start with the business logic and model the data to provide just enough to supply that logic.  See [Modeling business concepts](modeling-finance.md) for a more detailed review on modeling strategies in Elm.

## Testing the models

We can test the validity of our models directly in Elm using Elm's built in testing tools. Elm tests tend to be thinner than those of procedural and object-oriented languages since the Elm compiler eliminates the are large portion of the errors that occur in those languages.  If it compiles it will run without error, which means you're really just testing the validity of your logic.

The Morphir roadmap contains a significant amount of tools to give users confidence, including visualization, audit, and instant testing tools.

## Processing the models

Once the models are ready, the next step is to convert them whatever form they'll be executed in.  This is aspect of FDM utilizes techniques from Model-Driven Development in the form of code generation.  This is similar to the codegen phase of many projects when dealing with things like XSD, IDL, or OpenAPI processing. We refer to these as Dev Bots, since they are automating away many of the mundane and error prone aspects of development for which humans provide no value.  

## Incorporating into your code

One of the advantages of Morphir is that it is completely open, so teams can customize their own Dev Bots as needed for their projects.  Morphir has support for common Dev Bots to fit different paradigms of development.

### Micro integration: Libraries

The most basic approach to using Morphir is to have it generate from models into your project's language of choice.  This is analogous to writing your business logic as a set of libraries and using them from your handwritten code.  Morphir models can be generated into various target languages, which allows execution in different contexts with guaranteed consistency.

### Macro integration: Platforms

A more advanced use of Morphir is to use Dev Bots to target execution within an entire platform. Platform-level targets is a great way to ensure consistency and efficiency across the entire plant. Of course, this requires that Dev Bots exist for the target platforms. 