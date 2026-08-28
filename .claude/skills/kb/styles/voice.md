# Voice

Rules for every kb register. The register cards add structure on top; this card governs the sentences.

## Audience

Write for a junior to early mid-level developer. Do not require a PhD, and do not assume deep domain knowledge.
A reader who knows general programming should be able to follow the page.

When a claim needs background, supply it in this order:

1. Include the background on the page, in a few sentences.
2. Summarize it, then continue.
3. Link a Glossary or Data Dictionary. Preferred when that catalog lives in the same bundle or a co-located bundle (a sibling under the same grouping directory). That keeps the page moving and keeps definition sidebars off the narrative.
4. Link to another concept in this knowledge base.
5. Link an external reference. Least preferred. Allowed so the kb stays focused and does not grow a new page for every upstream detail.

Name the term, say what it is, then use it. A same-bundle or co-located Glossary or Data Dictionary link may stand in for that first sentence. A link to an unrelated concept or an external page may not.

## Mechanics

- Active voice, present tense. "The executor records the skip", not "the skip is recorded by the executor".
- One idea per sentence. When a sentence needs "and also" or a second clause to finish the thought, split it.
- Keep sentences short. Aim under 25 words; treat longer as a signal to split, not a hard failure.
- Keep paragraphs short: one topic, at most six sentences.
- Prefer concrete verbs: use, do, show, run, fail, keep. Not: utilize, perform, facilitate, enable, ensure.
- Name a concept once and keep that name. Do not rotate synonyms for variety; variety reads as a second concept.
- Define a term at first use, or link to the concept that defines it.
- State numbers, versions and units exactly. Pin factual claims to sources.
- Say who does what. "Sealing validates the graph" beats "validation occurs during sealing".

## Honesty

- Say what is unverified, and say it where the claim is made, not in a footnote.
- When sources disagree, record the disagreement. Do not smooth it over.
- No hedge stacking: "may potentially, in some cases" collapses to "may".

## Banned patterns

These read as machine-generated filler. Do not use them in kb content.

The em-dash is the one that appears most and is always avoidable. Nothing in this knowledge base needs
one: a comma, a colon, a pair of parentheses, or two sentences will carry the same meaning. Reach for
the split first, because a dash usually marks a sentence carrying two thoughts.

Rewriting is not the same as substituting. Replacing every dash with a comma produces comma-spliced
prose, which is its own tell. Decide per sentence, and drop the clause outright when it turns out to
be padding.

| Pattern | Instead |
| --- | --- |
| Em-dashes | Use a comma, colon, parentheses, or split the sentence |
| delve, dive deep, deep dive | read, examine, study |
| leverage, utilize | use |
| seamless, robust, powerful, cutting-edge | say the measurable property, or drop the adjective |
| crucial, critical (as emphasis) | say what breaks without it |
| comprehensive, holistic | say what is covered |
| landscape, ecosystem (as scene-setting) | name the actual systems |
| "It's worth noting", "Notably", "Importantly" | just state the fact |
| "In the world of X", "In today's Y" | delete the opener |
| "not just X, but Y" | state Y |
| load-bearing (figurative) | say what depends on it, or what breaks when it changes |
| Triads for rhythm ("fast, safe, and scalable") | keep the ones you can defend, drop the rest |
| A bolded topic phrase starting every bullet | write bullets as plain sentences |
| Closing summary that restates the page | end when the content ends |
| "Notice that", "Note that", "Observe that" | state the thing; the reader is already reading |
| deliberately, genuinely, actually, precisely, simply (as emphasis) | delete the word, or say who decided and why |
| "not X, it is Y" correcting a claim nobody made | state Y |
| A paragraph whose first clause restates the heading above it | start with the content |

The list is not a filter to run once at the end. Write without them.

## Scope

Applies to new kb content and to any document already being edited for another reason. Existing prose is
grandfathered until touched. Repository documents outside `kb/` follow their own conventions, though a
changelog that ships with a release is read as widely as anything in `kb/` and deserves the same care.

Nothing checks any of this. `morphir kb check` validates structure, frontmatter and links, not prose, so
the table above holds only as far as the author applies it. The gap is measurable: when this card was
adopted in the morphir-scala knowledge base, its authored content outside the mirrored `sources/`
subtrees already contained 826 em-dashes across 145 of its 159 files, written after this table existed.
Treat that as evidence about how easily the rules slip rather than as licence, and clean what you touch.
