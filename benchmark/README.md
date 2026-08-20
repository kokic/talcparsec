# talcparsec benchmarks

Run the benchmark package in release mode on the native backend:

```sh
moon bench benchmark --release --target native
```

Use the same command with `--target wasm-gc` to compare the project's preferred
backend. Keep the target, MoonBit version, machine load, and power settings
stable when comparing two revisions.

The suite covers these parser costs:

- exact and predicate-based scanning of a 4 KiB token;
- allocation-heavy `sep_by` parsing of 1,000 identifiers;
- flat and deeply nested recursive S-expression parsing;
- explicit backtracking across a long common prefix;
- construction and merging of diagnostics from 26 failed alternatives;
- zero-allocation whitespace skipping versus `spaces()` array collection;
- bitmap-based `one_of` membership scanning;
- `many_chars1` digit scanning (direct accumulation loop);
- error position lookup (line/column via `line_starts` binary search) on a
  2,048-line input;
- exact `string` match over a 4 KiB multi-line input.

Run one benchmark by index while investigating a regression:

```sh
moon bench --package kokic/talcparsec/benchmark \
  --file benchmark/parsec_bench_test.mbt --index 2 \
  --release --target native
```

Use `moon bench benchmark --build-only --release --target native` to verify the
benchmark package without collecting timings.
