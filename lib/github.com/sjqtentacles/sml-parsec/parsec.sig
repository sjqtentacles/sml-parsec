(* parsec.sig

   Applicative/monadic parser combinators for Standard ML, generic over an
   input STREAM. A `'a parser` consumes a prefix of a stream and either succeeds
   with a value of type `'a` (and a new stream position) or fails with an
   `error` describing where and what was expected.

   This signature is the result of `ParsecFn (S : STREAM)` and contains only the
   stream-agnostic core: sequencing, choice, repetition, and the two primitives
   `anyItem` and `sat` that read a single item via `S.uncons`. Character-level
   helpers (`char`, `string`, `digit`, `integer`, ...) live in `CharParsec`,
   which is built on `ParsecFn (CharStream)`.

   Choice (`<|>`) is *ordered* and does not backtrack once the right-hand parser
   has consumed input: `p <|> q` tries `q` only if `p` failed without consuming
   anything. Wrap a parser in `try` to make its failure non-consuming so that
   `<|>` can recover from it. This is the standard parsec semantics and is what
   makes error messages precise.

   The operator-named values below are exported as ordinary identifiers; a
   consumer must declare their `infix` status before using them in infix
   position (see the README), exactly as the implementation does internally. *)

signature PARSEC =
sig
  (* The input stream and its element type, fixed by the STREAM argument. *)
  type stream
  type item

  (* A source position: 1-based line and column, plus a 0-based offset. This is
     a concrete record shared by every stream instance (see STREAM). *)
  type pos = { line : int, col : int, off : int }

  (* What went wrong, and where. `expected` lists the labels/terminals the
     parser was hoping to see at `pos`; `msg` is an optional override message
     (e.g. from `fail`). *)
  type error = { pos : pos, expected : string list, msg : string option }

  type 'a parser

  datatype 'a result = Ok of 'a | Err of error

  (* Run a parser over an entire stream. Note this does NOT require the parser
     to consume all input; combine with `eof` if you want that guarantee. *)
  val runParser : 'a parser -> stream -> 'a result

  (* Render an error as a one-line human-readable string. *)
  val errorToString : error -> string

  (* ---- core ----------------------------------------------------------- *)

  val return : 'a -> 'a parser            (* succeed without consuming      *)
  val fail   : string -> 'a parser        (* fail with a message            *)
  val >>=    : 'a parser * ('a -> 'b parser) -> 'b parser   (* bind         *)
  val >>     : 'a parser * 'b parser -> 'b parser           (* sequence, keep 2nd *)
  val <*     : 'a parser * 'b parser -> 'a parser           (* sequence, keep 1st *)
  val <*>    : ('a -> 'b) parser * 'a parser -> 'b parser   (* applicative  *)
  val <$>    : ('a -> 'b) * 'a parser -> 'b parser          (* fmap         *)
  val <|>    : 'a parser * 'a parser -> 'a parser  (* ordered choice        *)
  val <?>    : 'a parser * string -> 'a parser     (* label for errors      *)

  (* Make a parser's failure non-consuming so `<|>` can recover. *)
  val try : 'a parser -> 'a parser

  (* ---- primitives ----------------------------------------------------- *)

  val anyItem : item parser                    (* any single item             *)
  val sat     : (item -> bool) -> item parser  (* an item matching a predicate *)
  val eof     : unit parser                     (* succeed only at end of input *)

  (* ---- combinators ---------------------------------------------------- *)

  val many     : 'a parser -> 'a list parser    (* zero or more                *)
  val many1    : 'a parser -> 'a list parser    (* one or more                 *)
  val optional : 'a parser -> 'a option parser
  val sepBy    : 'a parser -> 'b parser -> 'a list parser   (* p sep by sep    *)
  val sepBy1   : 'a parser -> 'b parser -> 'a list parser
  val between  : 'a parser -> 'b parser -> 'c parser -> 'c parser (* open close p*)

  (* Left-associative chaining: parse `p (op p)*` and fold the `op`s left.
     The workhorse for left-associative infix expression grammars. *)
  val chainl1  : 'a parser -> ('a * 'a -> 'a) parser -> 'a parser

  (* Defer construction of a parser until it is run. Essential for tying
     recursive grammar knots when the parser type is abstract: write
     `fun expr () = ... delay term ...` style definitions. *)
  val delay    : (unit -> 'a parser) -> 'a parser
end
