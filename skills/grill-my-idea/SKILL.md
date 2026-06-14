---
name: grill-my-idea
description: Grilling session that challenges your plan against the existing domain model and sharpens terminology. Use when user wants to stress-test a plan against their project's language and documented decisions.
---

<what-to-do>

Interview me relentlessly about every aspect of this plan until we reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one. For each question, provide your recommended answer.

Ask the questions one at a time, waiting for feedback on each question before continuing.

If a question can be answered by exploring the codebase, explore the codebase instead. Only ask questions a product owner or designer may be able to answer. Questions that are technical in nature and requires deep technical knowledge, or when the user responds that they do not know, must be included as open questions to the developer in the final product requirement document.

At the end, produce a complete product requirement document with all your findings that can be used for the implementation, and any new or changed CONTEXT entries that were defined during the session.

</what-to-do>

<supporting-info>

## Domain awareness

During codebase exploration, also look for existing documentation:

### File structure

Most repos have a single `CONTEXT.md`

If a `CONTEXT-MAP.md` exists at the root, the repo has multiple contexts. The map points to where each one lives.

If a repo does not yet have a `CONTEXT.md`, you can still suggest additions in the CONTEXT section, see Context Updates.

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `CONTEXT.md`, call it out immediately. "Your glossary defines 'cancellation' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'account' — do you mean the Customer or the User? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code cancels entire Orders, but you just said partial cancellation is possible — which is right?"

### Context updates

When a term is resolved, add it to the final product requirement document under a CONTEXT section. Don't batch these up — capture them as they happen in a temporary location, so you remember them for the final document. Use the format in [CONTEXT-FORMAT.md](./CONTEXT-FORMAT.md).

Don't couple `CONTEXT.md` to implementation details. Only include terms that are meaningful to domain experts.

</supporting-info>
