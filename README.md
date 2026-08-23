# <img src="./talc.svg" title="talcparsec" width=200 />

A fast, trait-driven parser combinator library for MoonBit.

talcparsec builds hand-written recursive-descent parsers out of small composable combinators. It targets the same niche as Parsec and Attoparsec: embedded languages, DSLs, interpreters, and source-code tooling where you want the structure of a grammar without a parser generator.

## Highlights

- **Commit-aware backtracking** — consuming input commits a parse attempt; once a branch commits, alternatives are no longer tried. Backtracking is opt-in via `attempt`, so failures never re-scan input silently.
- **Good errors by default** — failures carry the furthest position reached, and alternatives at the same position merge their expected labels. Every error is structured data (offset, line, column, expected labels, committed flag), so diagnostics are easy to render or recover from.
- **Open error model** — `ParserRaw[I, T, E]` is generic over input, result, and error type. A custom error type only needs the `Commit + CanMerge + Positioned + ParseFailure` traits; the full combinator stack and the primitive parsers work with any `E`.
- **Fast on hot paths** — tokenizer loops avoid allocation, line and column positions are computed lazily from a line-start table, and all offsets are UTF-16 code units matching MoonBit string indexing.

## Add as a dependency

```
moon add kokic/talcparsec
```

## Design

### Trait-based error hierarchy

The error model is four layered traits, all implemented by the default `ParseError` struct:

- `Commit` — whether a failure forbids backtracking;
- `CanMerge` — how two failures at the same position combine;
- `Positioned` — the source position of a failure;
- `ParseFailure` — construction from an input cursor, with `signal` (expected-label failures) and `message` (free-form failures).

Because the combinators are written against the traits rather than the concrete error type, an application can substitute its own error type — with structured payloads of its choosing — and use every built-in combinator and primitive unchanged.

### Input as a trait

Parsers are parameterized over the `Cursor` trait (`cursor`, `position`, `is_at_eof`, `same_cursor`), so the same combinators work on the built-in string `Input` and on custom token streams.

### Explicit control flow

There is no hidden backtracking. A parser either commits (input was consumed) or fails uncommitted; `attempt` clears the commit so the next alternative is tried. `label` improves error messages without backtracking, and `not_followed_by` provides negative lookahead. Repetition combinators reject parsers that accept empty input instead of looping forever.
