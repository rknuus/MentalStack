## Interaction rules

- Ask clarifying questions if input is unclear
- Explain why and suggest alternatives if task is not feasible
- Use structured, readable formatting (headings, lists, code blocks)
- Follow instructions closely and explain clearly what you have done
- Don't modify code unrelated to the current task
- Try always to match the style of the code you are touching
- When refactoring, never modify test assertions, only the implementation

## Coding standards

- Write meaningful tests with assertions for all code
- Avoid duplicate assertions
- Maintain evolving code coverage
- Apply Four Rules of Simple Design:
  - Code works (passes tests)
  - Reveals intent
  - No duplication
  - Minimal elements
- Prefer functional style:
  - Use explicit parameters
  - Prefer immutability
  - Prefer declarative over imperative
  - Minimize state

## Architecture

- Modularize by concern, not by technical layer
- One responsibility per module
- Low inter-module coupling
- Short functions, no overengineering

## Workflow

- Write and pass tests before finalizing
- When refactoring: never modify test assertions, only the implementation
- Lint code before finalizing
- Keep a `README.md` with usage/setup/run info
- Store documents in Markdown

## Commit strategy

Each commit:
- self-contained
- includes tests
- uses 50/70 commit message format

## Safe practices

- Do not change test assertions during refactoring
- Do not skip failing tests
- Do not invent unknown APIs, look up or ask if you are unsure

## Project-Specific Instructions
