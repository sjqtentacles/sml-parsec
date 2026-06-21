(* parsec.sig

   Applicative/monadic parser combinators for Standard ML, with position
   tracking and human-readable error reporting.

   A `'a parser` consumes a prefix of a string and either succeeds with a value
   of type `'a` (and a new position) or fails with an `error` describing where
   and what was expected.

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
  (* A source position: 1-based line and column, plus a 0-based byte offset. *)
  type pos = { line : int, col : int, off : int }

  (* What went wrong, and where. `expected` lists the labels/terminals the
     parser was hoping to see at `pos`; `msg` is an optional override message
     (e.g. from `fail`). *)
  type error = { pos : pos, expected : string list, msg : string option }

  type 'a parser

  datatype 'a result = Ok of 'a | Err of error

  (* Run a parser over an entire string. Note this does NOT require the parser
     to consume all input; combine with `eof` if you want that guarantee. *)
  val runParser : 'a parser -> string -> 'a result

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

  val anyChar : char parser
  val sat     : (char -> bool) -> char parser  (* a char matching a predicate *)
  val char    : char -> char parser
  (* Match an exact string. Atomic: on a partial match it fails WITHOUT
     consuming input, so a surrounding `<|>` can still try alternatives
     (no explicit `try` needed around `string`). *)
  val string  : string -> string parser
  val oneOf   : string -> char parser          (* any char in the set         *)
  val noneOf  : string -> char parser          (* any char not in the set     *)
  val digit   : char parser
  val letter  : char parser
  val spaces  : unit parser                     (* zero or more whitespace     *)
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

  (* Lexeme helper: parse `p` then skip trailing whitespace. *)
  val token    : 'a parser -> 'a parser

  (* Defer construction of a parser until it is run. Essential for tying
     recursive grammar knots when the parser type is abstract: write
     `fun expr () = ... delay term ...` style definitions. *)
  val delay    : (unit -> 'a parser) -> 'a parser

  (* Parse a (possibly signed) integer. *)
  val integer  : int parser
end
