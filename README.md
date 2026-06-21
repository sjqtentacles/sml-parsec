# sml-parsec

[![CI](https://github.com/sjqtentacles/sml-parsec/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-parsec/actions/workflows/ci.yml)

Parser combinators for Standard ML, with position tracking and precise error
reporting.

`sml-parsec` is a small applicative/monadic parser-combinator library in the
tradition of Haskell's Parsec. You build parsers compositionally from tiny
primitives, and the library tracks source positions and accumulates an
"expected" set so failures point at the real problem.

## Semantics

Choice (`<|>`) is **ordered** and committed-on-consume, exactly like Parsec:

- `p <|> q` tries `q` only if `p` failed **without consuming input**.
- If `p` failed having already consumed input, that failure is propagated (the
  parser is "committed"). This keeps error messages precise.
- Wrap a parser in `try` to make its failure non-consuming, so a surrounding
  `<|>` can recover and try the alternative.

`string` is atomic: a partial match fails without consuming, so you rarely need
`try` around it.

## Operators and infix status

The operator-named values (`>>=`, `>>`, `<*`, `<*>`, `<$>`, `<|>`, `<?>`) are
exported as ordinary identifiers. Before using them in infix position, declare
their fixity (these match what the library uses internally):

```sml
infix 1 >>= >>
infix 1 <*
infix 4 <*> <$>
infixr 1 <|>
infix 0 <?>
open Parsec
```

## Portability

Pure Standard ML using only the Basis library. Verified on:

- **MLton**
- **Poly/ML**

The sources are shared via an [ML Basis](http://mlton.org/MLBasis) (`.mlb`)
file. MLton consumes it natively; for Poly/ML the test target simply `use`s
the sources in order.

## Building and testing

```sh
make test        # build + run the suite under MLton (default)
make test-poly   # run the suite under Poly/ML
make all-tests   # run under both
make clean
```

## Installing with smlpkg

`sml-parsec` follows the conventions of the
[`smlpkg`](https://github.com/diku-dk/smlpkg) package manager. There is no
registry or account to sign up for -- packages are referenced directly by
their git URL. In your own project's directory:

```sh
smlpkg add github.com/sjqtentacles/sml-parsec
smlpkg sync
```

This downloads the library into `lib/github.com/sjqtentacles/sml-parsec/`.
Reference it from your own `.mlb` with a relative path to `parsec.mlb`:

```
lib/github.com/sjqtentacles/sml-parsec/parsec.mlb
```

For Poly/ML, `use` the sources in order:

```sml
use "lib/github.com/sjqtentacles/sml-parsec/parsec.sig";
use "lib/github.com/sjqtentacles/sml-parsec/parsec.sml";
```

## Usage

A whitespace-tolerant arithmetic evaluator with correct precedence and
left-associativity, in a few lines:

```sml
infix 1 >>= >>
infix 1 <*
infix 4 <*> <$>
infixr 1 <|>
infix 0 <?>
open Parsec

fun calc () =
  let
    val addop = token ((char #"+" >> return (op +)) <|> (char #"-" >> return (op -)))
    val mulop = token ((char #"*" >> return (op * )) <|> (char #"/" >> return (op div)))
    fun expr () = chainl1 (delay term) addop
    and term () = chainl1 (delay factor) mulop
    and factor () =
          token integer
          <|> between (token (char #"(")) (token (char #")")) (delay expr)
  in
    spaces >> (delay expr <* eof)
  end

val Ok n = runParser (calc ()) "2 * (3 + 4) - 1"   (* n = 13 *)
```

Note `delay : (unit -> 'a parser) -> 'a parser`, which ties recursive grammar
knots when the parser type is abstract.

Inspecting errors:

```sml
case runParser (calc ()) "1 + * 2" of
    Ok n  => print (Int.toString n ^ "\n")
  | Err e => print (errorToString e ^ "\n")
(* parse error at line 1, column 5: ... *)
```

## API highlights

- Core: `return`, `fail`, `>>=`, `>>`, `<*`, `<*>`, `<$>`, `<|>`, `<?>`, `try`
- Primitives: `anyChar`, `sat`, `char`, `string`, `oneOf`, `noneOf`, `digit`,
  `letter`, `spaces`, `eof`, `integer`
- Combinators: `many`, `many1`, `optional`, `sepBy`, `sepBy1`, `between`,
  `chainl1`, `token`, `delay`
- Driver: `runParser`, `errorToString`

## Project layout

```
sml.pkg                                         smlpkg manifest
Makefile                                        build + test
lib/github.com/sjqtentacles/sml-parsec/
  parsec.sig                                    the PARSEC signature
  parsec.sml                                    the implementation
  parsec.mlb                                    MLB for consumers
test/
  test.mlb                                      test basis (MLton)
  test.sml                                      assertion suite
.github/workflows/ci.yml                        CI (MLton + Poly/ML)
```

## License

MIT. See [LICENSE](LICENSE).
