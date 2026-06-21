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
the common case of parsing strings, use the ready-made `CharParsec` structure,
which also bundles a [lexer/token kit](#lexer--token-kit) and an
[expression-parser builder](#expression-parser-builder). Every operator has a
[prefix-named alias](#zero-fixity-ergonomics) so grammars can be written with no
`infix` declarations at all.

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
open CharParsec
```

### Zero-fixity ergonomics

If you would rather not declare any fixities, every operator has a curried,
prefix-named alias, so a whole grammar can be written without an `infix` block:

| operator | alias | type |
| --- | --- | --- |
| `>>=` | `andThen`  | `'a parser -> ('a -> 'b parser) -> 'b parser` |
| `>>`  | `seqRight` | `'a parser -> 'b parser -> 'b parser` |
| `<*`  | `seqLeft`  | `'a parser -> 'b parser -> 'a parser` |
| `<*>` | `ap`       | `('a -> 'b) parser -> 'a parser -> 'b parser` |
| `<$>` | `map`      | `('a -> 'b) -> 'a parser -> 'b parser` |
| `<|>` | `orElse`   | `'a parser -> 'a parser -> 'a parser` |
| `<?>` | `label`    | `'a parser -> string -> 'a parser` |

```sml
open CharParsec   (* no infix declarations needed *)

(* a signed integer, then end of input *)
val signedInt = orElse (seqRight (char #"~") (map (fn n => ~n) integer)) integer
val full      = seqLeft (seqRight spaces signedInt) eof
val Ok n      = runParser full "~42"   (* n = ~42 *)
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
use "lib/github.com/sjqtentacles/sml-parsec/charparseccore.sml";
use "lib/github.com/sjqtentacles/sml-parsec/charparsec.sig";
use "lib/github.com/sjqtentacles/sml-parsec/charparsec.sml";
use "lib/github.com/sjqtentacles/sml-parsec/expr.sig";
use "lib/github.com/sjqtentacles/sml-parsec/exprfn.sml";
use "lib/github.com/sjqtentacles/sml-parsec/charexpr.sml";
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

## Lexer / token kit

`CharParsec` ships a small lexer kit so you do not have to hand-roll the usual
whitespace and punctuation plumbing. A *lexeme* is a parser that skips trailing
whitespace; `lexeme` is the canonical name (the old `token` is kept as an
alias).

```sml
open CharParsec

val ident = identifier Char.isAlpha Char.isAlphaNum   (* first/rest predicates *)

(* parse `let x = (1, 2, 3)` shapes *)
val binding =
  keyword "let" >> ident >>= (fn name =>
    symbol "=" >> parens (commaSep (lexeme integer)) >>= (fn nums =>
      return (name, nums)))

val Ok ("x", [1,2,3]) = parse binding "let x = (1, 2, 3)"
```

Kit members: `lexeme` (= `token`), `symbol`, `parens` / `brackets` / `braces`,
`identifier`, `keyword` (rejects e.g. `lettuce` for keyword `let`),
`commaSep` / `commaSep1`, `semiSep` / `semiSep1`. The `parse` driver skips
leading whitespace, runs the parser, and requires end of input -- unlike
`runParser`, which permits trailing input.

## Expression parser builder

`buildExpressionParser` turns a precedence table into a parser, so you do not
have to write the `chainl1` / `chainr1` ladder by hand. It is a functor
`ExprParserFn (P : PARSEC)`; the character instance is `CharExpr`, whose parsers
unify with `CharParsec`'s.

```sml
open CharParsec
open CharExpr   (* assoc, the `operator` constructors, buildExpressionParser *)

(* table is HIGHEST precedence first *)
fun mulop () = lexeme (char #"*") >> return (op * )
fun addop () = lexeme (char #"+") >> return (op +)
fun subop () = lexeme (char #"-") >> return (op -)
fun table () =
  [ [ Infix (mulop (), LeftAssoc) ],
    [ Infix (addop (), LeftAssoc), Infix (subop (), LeftAssoc) ] ]
fun factor () = lexeme integer <|> parens (delay exprP)
and exprP () = buildExpressionParser (table ()) (delay factor)

val Ok 14 = parse (delay exprP) "2 + 3 * 4"
```

`operator` covers `Infix of (... ) parser * assoc` (with
`assoc = LeftAssoc | RightAssoc | NonAssoc`), `Prefix`, and `Postfix`, so
right-associative operators (`Infix (powop, RightAssoc)`) and prefix unary
operators (`Prefix negate`) drop straight into the table.

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
  `<*>`, `<$>`, `<|>`, `<?>`, `try`, `anyItem`, `sat`, `eof`, `runParser`,
  `errorToString`
- Named aliases (no fixity needed): `andThen`, `seqRight`, `seqLeft`, `ap`,
  `map`, `orElse`, `label`
- Combinators: `many`, `many1`, `optional`, `option`, `choice`, `count`,
  `manyTill`, `notFollowedBy`, `skipMany`, `skipMany1`, `sepBy`, `sepBy1`,
  `endBy`, `endBy1`, `sepEndBy`, `sepEndBy1`, `between`, `chainl1`, `chainr1`,
  `chainl`, `chainr`, `delay`
- Character layer (`CharParsec`): all of the above plus `anyChar`, `char`,
  `string`, `oneOf`, `noneOf`, `digit`, `letter`, `spaces`, `integer`, a
  `string`-based `runParser`, and the lexer kit: `lexeme` (= `token`), `symbol`,
  `parens`, `brackets`, `braces`, `identifier`, `keyword`, `commaSep`,
  `commaSep1`, `semiSep`, `semiSep1`, and the full-input `parse` driver
- Expression builder (`ExprParserFn` functor; `CharExpr` instance):
  `buildExpressionParser`, `assoc`, `operator` (`Infix` / `Prefix` / `Postfix`)
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
  charparseccore.sml                            ParsecFn(CharStream) as a named core
  charparsec.sig                                CHAR_PARSEC signature
  charparsec.sml                                CharParsec (chars + lexer kit + runParser)
  expr.sig                                      the EXPR_PARSER signature
  exprfn.sml                                    ExprParserFn functor (precedence tables)
  charexpr.sml                                  CharExpr = ExprParserFn(CharParsecCore)
  tokenstream.sml                               ListStream functor
  parsec.mlb                                    MLB for consumers
test/
  test.mlb                                      test basis (MLton)
  test.sml                                      assertion suite
.github/workflows/ci.yml                        CI (MLton + Poly/ML)
```

## License

MIT. See [LICENSE](LICENSE).
