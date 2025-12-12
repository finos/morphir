---
sidebar_position: 2
id: background-story
title: The Morphir Background Story
---

# The Morphir Background Story

Morphir evolved from years of frustration trying to work around technical limitations to adequately model business concepts. Then after so much effort and pain, we inevitably have to start over to adapt to some new technology. This came to a head when one of our businesses suddenly faced a convergence of major new business requirements and technical upgrades that required yet another major rewrite. There was so much work to be done and so much frustration from our business clients that they issued the challenge below...

## The Challenge

> **Stop the cycle of rewrites** - Our users recognized that we were in a constant cycle of upgrading technology. Each pass in the cycle required significant effort and posed the risk of implementing core business logic incorrectly.

> **Stop making us use multiple applications with inconsistent values** - Our users noticed that different systems came to different results for what should have theoretically been the same calculations. As a result, they had to navigate across applications to get the information they needed.

> **Show us that the system is behaving correctly** - Our users demanded that if we were going to rewrite core business logic again, we needed to provide transparency so that they could understand exactly how the system was behaving with respect to the business.

> **Deliver faster** - A never ending, desired request.

## Common Cause

This challenge made us re-examine our whole development process. It soon became clear that there was a theme across them: **the fundamental issue was the fact that the business knowledge was tightly wrapped into the technologies of the moment**. It stood to reason that freeing the business knowledge from the technology would address these challenges. That's the approach we took and that is what eventually evolved into Morphir.

## Morphir In Action

Let's take a look at what that all means and how Morphir works to address these challenges. Let's consider a component of an online store application. The purpose of this application is to decide on:

### Promoting Business Knowledge

The business concepts underlying your application are its most valuable asset. It's often difficult to discern
business concepts when they're embedded within platform and execution code. On top of that, many programming languages
are so full of abstractions that it can become difficult to understand the business meaning at all.

Morphir tackles this challenge in a few ways. First, it provides a common structure to save business concepts, including
both data and logic. This is the Morphir IR. The key to this structure is that it focuses solely on business logic and
data. No side effects (like saving to a database or reading from a file) are allowed. The IR is the core to Morphir and
allows it to work across languages and platforms.

Having an application's business knowledge in a common data structure allows teams to build useful tools that promote
knowledge dissemination. Some useful examples include interactive visualizations that allow users to understand the
application's logic, interactive audit tools to replay calculations interactively, automatic data dictionary and data
lineage registration, and more.

The combination of these creates an ecosystem where users, new developers, and support personnel can gain insight into
an application interactively without requiring developers to go back and study stale documentation and arcane code.

### Showing Correctness

If you're going to treat business knowledge as a valuable asset, you want to make sure that it's correct. Morphir's use
of functional programming structures that are tuned towards codifying business concepts eliminates many of the bugs that
are common in less concise tools. This is really just the beginning of the story. What's even more powerful is the fact
that Morphir is compatible with a variety of source languages, so it can take advantage of the powerful tools that they
offer. We currently support the [Elm programming language](http://elm-lang.org) due to its simplicity and power. The Elm
compiler is supercharged to catch huge classes of bugs. The common saying is that if it compiles, it's guaranteed not to
have runtime errors (excluding limitations of the physical environment, of course). Another particularly exciting
language is Microsoft's [Bosque programming language](https://github.com/microsoft/BosqueLanguage), which takes the
ability to verify program correctness up whole other level. Keep an eye out for further progress in this space.

Finally, the aforementioned business knowledge tools are a big help in establishing correctness. When users have the
ability to fully understand the system with helpful tools in real-time, it makes the user/developer feedback cycle very
efficient.

### Delivering Faster

An important role of developers is to decide how the business concepts fit into an executable computer system. Once
that shape is decided, a great deal of the actual coding is very repetative and templated. Add to this the various best
practices and team standards and you get a lot of boilerplate code that can be automated for faster production with
fewer errors. Morphir relies heavily on such automation, which we call Dev Bots. As with any automation, smart use can
lead to drastic efficiency improvements, like taking seconds to generate what a developer would take days to
produce. Check out the [Dev Bot post](dev-bots) for more information on this topic.

### Eliminating Rewrites

Technology is evolving ever more quickly. It is no longer feasible to stay competitive if you need to completely rewrite
you application every time you want to upgrade to newer technologies. That's especially true if there is a risk of
getting your core business logic wrong in a rewrite. In addition to automating boilerplate code, Morphir Dev Bots convert
Morphir IR into system code. This means the same Morphir model can run in different technologies. And with the business
concepts protected in the Morphir model, there's no risk to losing it with the next big technology. Keep an eye out for
the evolving list of target environments available in the Morphir ecosystem. Or, if you need something that's not there,
Morphir provides the tools to do it yourself.

# Summing Up

Hopefully this gives a good background into what Morphir does and why. If you have any questions or comments, feel free
to drop us a note through the [Morphir project](https://github.com/finos/morphir).

[Home](/index) | [Posts](posts) | [Examples](https://github.com/finos/morphir-examples/)
