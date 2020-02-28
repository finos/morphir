# Welcome to Morphir

## What is it?
Morphir is an open-source implementation of the Functional Domain Modeling (FDM) method of development.  It's goal is to allow teams to gain the advantages of FDM while adopting it at their own pace.

FDM is an approach to business application development that treats an application's business concepts as first-class assets worthy of special handling.  It combines aspects of Domain-Driven Design, Model-Driven Development, and Functional Programming into a process where the business concepts are captured in the business terms.

## Why should anyone consider using it?
Have you ever run into these problems?
* You're stuck in a **cycle of major rewrites** just trying to keep pace with the pace of technology process.
* **Nobody understands how the system works** holistically.
* Only **one person understands the system** and that person just left the company.
* You need **consistent behavior across componants or systems** but writing them in multiple languages gets out of sync.
* Even with firm-wide best practices, guides, and blueprints, teams using the same technologies still built **vastly different systems** and the resulting support costs are significant.
* You spend an inordinate amount of **time on hygiene tasks** (upgrading libraries, keeping up with firm standards, etc.).
* You're writing a new system and are spending a lot of effort **choosing the "right" technologies** before you even start.
* Your **code has no discernable relation to your business**.
* Your **business planning is based on what your technology allows** instead of your technology planning being based on the business needs.
* Your team spends too much time **writing non-functional platform code that has no direct business value**.

These are amongst a set of recurring themes across enterprise application development.  These are the challenges that Morphir targets.

## How does it work?
Morphir is centered around the realization that all of these symptoms stem from the same cause
**Our business concepts are tightly coupled with our technology choices.**

Morphir targets this by formally separating the definition of business concepts from the execution.  This allows the business and the technology to evolve independently without putting each other at risk.  It does this by modeling the business concepts in a distinct phase of the development process.  That model, which includes both business and logic, is captured in a common data structure (an Intermediary Representation or IR) that allows it to be processed into a range of target technologies.  It is essentially a combination of Domain-Driven Design, Model-Driven Development, and Functional Programming.  The result is that developers can model their code in the language of the business using a full programming language and have that run with provably consistent behavior in various exection platforms.

## What can we do with it?
* **Model entire distributed applications that can run in a variety of current and future environments without rewriting the code.**
* **Automate compliance with hygiene and best practices without burdening development teams**
* **Automate application infrastructure optimization based on measurement and monitoring**
* **Share logic and rules across teams running different technology stacks**
* **Automate transparency and audit tools** to explain data lineage, what changed, and *why*.
* **Automate analysis of what branches of a formula caused result changes over time.**
* **Provide users and developers of immediate feedback on the impact of rule changes.**
* **Automate interactive documentation that explains the exact logic of the current version of the software.**
* **Use advanced verification tools to prove the correctness of your applications.**
