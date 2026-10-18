# Morphir IR

Morphir IR describes types, values and packages independently of a source language or execution platform.

## Language

**Format version**:
The release of the IR representation used by a document. It is independent of a tooling release.

**Current IR**:
The latest IR model supported by this implementation. Its meaning advances when support for a newer model is added.

**Versioned IR**:
An IR document whose format version remains explicit, including historical representations.

**Specification**:
The public types and value signatures of a module or package.

**Definition**:
The implementation of a type, value, module or package.

**Portable value definition**:
A value implementation expressed in Morphir IR, independent of a particular runtime host.

**Runtime binding**:
A host or SDK implementation of a named Morphir value for a specific execution target.

**Hybrid value definition**:
A value with both a portable implementation and one or more optional runtime bindings.

**Distribution**:
A package delivered as a library, a specification, or an application with entry points.

**Compilation unit**:
The complete source set compiled together for one Morphir package, with an explicit package and dependency context.
_Avoid_: Compiled model, individual source file when the compilation includes several documents

**Morphir model**:
An identified logical pipeline value containing a versioned distribution, metadata, annotations and provenance. It can be created, enriched, transformed, analyzed, evaluated or consumed by a generator independently of its storage or transport encoding.
_Avoid_: IRModel, unit, compilation unit, model envelope

**Model revision**:
A particular state of a Morphir model to which facts and guarantees apply. Its identity distinguishes it from other states of the same logical model.

**Model guarantee**:
A property established for a model revision within a stated scope and dependency context. Later changes may preserve or invalidate it.
_Avoid_: Unchecked state label, capability claim

**Model enrichment**:
Information added to a Morphir model, such as source origins, naming facts, numeric precision or analysis results. An enrichment establishes a guarantee only when its evidence has been validated.

**Model envelope**:
The representation used to store or transmit a Morphir model, with the format and integrity information required by that representation.
_Avoid_: Compilation unit, semantic distribution

**Migration**:
An explicit conversion between IR format versions. A conversion that cannot retain the represented information is refused.

**Morphir Scheme**:
An embeddable language for transformation scripts and an execution target for Morphir IR.

**Pipeline**:
An ordered frontend, IR transformations and backend applied to a source by the engine.

**Project**:
A named unit of source, configuration and pipeline execution.

**Workspace**:
A root that defines project membership, shared configuration and output ownership. It may contain a root project.

**Host**:
The embedding environment that supplies external capabilities and controls their lifetime.

**Artifact**:
A named output returned by a backend, ready for the host to persist or consume.

**Execution plan**:
The resolved projects, sources, configuration and stages for one invocation.

**Publication**:
Making a completed set of artifacts available at its destination.

## Runtime capabilities

**Runtime capabilities**:
The operations, features and behavior a runtime/provider supports under stated conditions. They are separate from model guarantees, host authority and business correctness.

**Capability claim**:
A provider-authored assertion about supported operations, features or behavior. The claim and the evidence checking it are distinct.

**Capability claim set**:
A provider-authored collection of capability claims, including the provider's identity and available operations, languages and supported behavior.
_Avoid_: Capability statement, verified support without scoped evidence

**Capability verification**:
Gathering scoped contract and compatibility evidence that an implementation behaves as its provider claims. This evidence is not formal proof of correctness for all programs or business outcomes.

**Capability validation**:
Checking that a chosen runtime/provider's capabilities meet the requirements of a particular run, selected function and model revision, before or as execution proceeds under policy.

**Capability check**:
A check of a required runtime feature against the chosen runtime/provider's capabilities. Policy determines when an unsupported requirement must refuse a run.

**Capability checking policy**:
The scope and timing of capability validation for a run. "Whole model before running" checks the model up front; "As code executes" checks required behavior when execution reaches it. Both retain mandatory identity, integrity, input/output boundary and resource checks.
_Avoid_: Admission policy, unrestricted execution, tree shaking

## Frontend selection

**Source language**:
The language of the submitted source documents, independent of the provider or the subset it supports. MoonBit remains one source language as its support grows.
_Avoid_: Frontend profile, provider name

**Frontend provider**:
An implementation of source-to-IR compilation for one or more source languages. Several providers may support the same language with different capabilities.
_Avoid_: Source language, frontend profile

**Frontend profile**:
A named, versioned contract defining an accepted source subset and its lowering semantics. A provider may offer several profiles for the same source language.
_Avoid_: Language variant, provider identity

**IR capability set**:
A declaration of the IR features a frontend emits, a backend accepts or a transform consumes and produces, using the IR specification's feature vocabulary.
_Avoid_: Source language, profile name, implementation-specific feature flags
