# sml-parsec

[![CI](https://github.com/sjqtentacles/sml-parsec/actions/workflows/ci.yml/badge.svg)](https://github.com/sjqtentacles/sml-parsec/actions/workflows/ci.yml)

Parser combinators for Standard ML, generic over the input stream, with
position tracking and precise error reporting.

`sml-parsec` is a small applicative/monadic parser-combinator library in the
tradition of Haskell's Parsec. You build parsers compositionally from tiny
primitives, and the library tracks source positions and accumulates an
"expected" set so failures point at the real problem.

As of **v0.3.0** the core is a functor `ParsecFn (S : STREAM)` over an abstract
input `STREAM`, so the same combinators parse character streams, token streams
produced by a separate lexer, or anything else you can express as `uncons`. For
the common case of parsing strings, use the ready-made `CharParsec` structure.

> **Breaking change in v0.3.0.** The old `structure Parsec` (string-only) is
> gone. For string parsing, `open CharParsec` instead of `open Parsec` -- the
> combinator and primitive names are unchanged, so existing grammars port by
> changing only that one line. `runParser` still takes a `string` in
> `CharParsec`. To parse other streams, instantiate `ParsecFn` with your own
> `STREAM`.

## The STREAM model

A parser runs over a value satisfying the `STREAM` signature:

```sml
signature STREAM = sig
  type stream
  type item
  type pos = { line : int, col : int, off : int }
  val uncons   : stream -> (item * stream) option
  val pos      : stream -> pos
  val showItem : item -> string
  val showPos  : pos -> string
end
```

`ParsecFn (S : STREAM)` yields the generic `PARSEC` core (sequencing, choice,
repetition, plus the two stream primitives `anyItem` and `sat`). `pos` is a
single concrete record shared by all streams: `off` gives the total order used
to report the furthest failure; `line`/`col` are for messages. The library
ships two instances:

- `CharStream : STREAM` (item = `char`) with real line/column tracking, wrapped
  by `CharParsec` which adds `char`, `string`, `digit`, `integer`, ... and a
  `string`-based `runParser`.
- `ListStream` (a functor `(type t val show : t -> string)`) for parsing a list
  of tokens; `off`/`col` are the token index.

## Semantics

Choice (`<|>`) is **ordered** and committed-on-consume, exactly like Parsec:

- `p <|> q` tries `q` only if `p` failed **without consuming input**.
- If `p` failed having already consumed input, that failure is propagated (the
  parser is "committed"). This keeps error messages precise.
- Wrap a parser in `try` to make its failure non-consuming, so a surrounding
  `<|>` can recover and try the alternative.

`CharParsec.string` is atomic: a partial match fails without consuming, so you
rarely need `try` around it.

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

For Poly/ML, `use` the sources in dependency order:

```sml
use "lib/github.com/sjqtentacles/sml-parsec/stream.sig";
use "lib/github.com/sjqtentacles/sml-parsec/parsec.sig";
use "lib/github.com/sjqtentacles/sml-parsec/parsecfn.sml";
use "lib/github.com/sjqtentacles/sml-parsec/charstream.sml";
use "lib/github.com/sjqtentacles/sml-parsec/charparsec.sig";
use "lib/github.com/sjqtentacles/sml-parsec/charparsec.sml";
use "lib/github.com/sjqtentacles/sml-parsec/tokenstream.sml";  (* optional *)
```

## Usage

A whitespace-tolerant arithmetic evaluator with correct precedence and
left-associativity, in a few lines (note `open CharParsec`):

```sml
infix 1 >>= >>
infix 1 <*
infix 4 <*> <$>
infixr 1 <|>
infix 0 <?>
open CharParsec

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

## Parsing a token stream

The same combinators run over any `STREAM`. Lex your input into a token list,
then instantiate `ParsecFn` with `ListStream`:

```sml
infix 1 >>= >>
infix 1 <*
infixr 1 <|>

datatype tok = TNum of int | TPlus | TStar | TLParen | TRParen
fun showTok (TNum n) = Int.toString n
  | showTok TPlus = "+" | showTok TStar = "*"
  | showTok TLParen = "(" | showTok TRParen = ")"

structure TokStream = ListStream (type t = tok val show = showTok)
structure TP = ParsecFn (TokStream)
local open TP in
  val num  = sat (fn TNum _ => true | _ => false)
             >>= (fn TNum n => return n | _ => fail "number")
  val plus = sat (fn TPlus => true | _ => false) >> return (op +)
  val star = sat (fn TStar => true | _ => false) >> return (op * )
  val lpar = sat (fn TLParen => true | _ => false)
  val rpar = sat (fn TRParen => true | _ => false)
  fun expr () = chainl1 (delay term) plus
  and term () = chainl1 (delay factor) star
  and factor () = num <|> between lpar rpar (delay expr)
end

(* 2 + 3 * 4 = 14 *)
val TP.Ok n =
  TP.runParser (TP.delay expr) { toks = [TNum 2, TPlus, TNum 3, TStar, TNum 4], idx = 0 }
```

## API highlights

- Generic core (`PARSEC`, from `ParsecFn`): `return`, `fail`, `>>=`, `>>`, `<*`,
  `<*>`, `<$>`, `<|>`, `<?>`, `try`, `anyItem`, `sat`, `eof`, `many`, `many1`,
  `optional`, `sepBy`, `sepBy1`, `between`, `chainl1`, `delay`, `runParser`,
  `errorToString`
- Character layer (`CharParsec`): all of the above plus `anyChar`, `char`,
  `string`, `oneOf`, `noneOf`, `digit`, `letter`, `spaces`, `token`, `integer`,
  and a `string`-based `runParser`
- Streams: `CharStream`, `ListStream` (functor)

## Project layout

```
sml.pkg                                         smlpkg manifest
Makefile                                        build + test
lib/github.com/sjqtentacles/sml-parsec/
  stream.sig                                    the STREAM signature
  parsec.sig                                    the generic PARSEC signature
  parsecfn.sml                                  ParsecFn functor (the core)
  charstream.sml                                CharStream : STREAM
  charparsec.sig                                CHAR_PARSEC signature
  charparsec.sml                                CharParsec (chars + runParser)
  tokenstream.sml                               ListStream functor
  parsec.mlb                                    MLB for consumers
test/
  test.mlb                                      test basis (MLton)
  test.sml                                      assertion suite
.github/workflows/ci.yml                        CI (MLton + Poly/ML)
```

## License

MIT. See [LICENSE](LICENSE).
