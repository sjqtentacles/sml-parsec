(* charparsec.sig

   The character-level parser interface: the full generic PARSEC core
   instantiated at `CharStream`, plus character-specific primitives and a
   `runParser` that accepts a plain `string`.

   This is the interface most consumers want. Build grammars from `char`,
   `string`, `digit`, `integer`, ... and the combinators inherited from PARSEC
   (`>>=`, `<|>`, `many`, `chainl1`, `between`, ...). *)

signature CHAR_PARSEC =
sig
  type pos = { line : int, col : int, off : int }
  type error = { pos : pos, expected : string list, msg : string option }
  type 'a parser

  datatype 'a result = Ok of 'a | Err of error

  (* Run a parser over a whole string. Does NOT require consuming all input;
     combine with `eof` for that guarantee. *)
  val runParser : 'a parser -> string -> 'a result
  val errorToString : error -> string

  (* ---- core (inherited from PARSEC) ---------------------------------- *)
  val return : 'a -> 'a parser
  val fail   : string -> 'a parser
  val >>=    : 'a parser * ('a -> 'b parser) -> 'b parser
  val >>     : 'a parser * 'b parser -> 'b parser
  val <*     : 'a parser * 'b parser -> 'a parser
  val <*>    : ('a -> 'b) parser * 'a parser -> 'b parser
  val <$>    : ('a -> 'b) * 'a parser -> 'b parser
  val <|>    : 'a parser * 'a parser -> 'a parser
  val <?>    : 'a parser * string -> 'a parser
  val try    : 'a parser -> 'a parser

  val anyItem : char parser
  val sat     : (char -> bool) -> char parser
  val eof     : unit parser

  val many     : 'a parser -> 'a list parser
  val many1    : 'a parser -> 'a list parser
  val optional : 'a parser -> 'a option parser
  val sepBy    : 'a parser -> 'b parser -> 'a list parser
  val sepBy1   : 'a parser -> 'b parser -> 'a list parser
  val between  : 'a parser -> 'b parser -> 'c parser -> 'c parser
  val chainl1  : 'a parser -> ('a * 'a -> 'a) parser -> 'a parser
  val delay    : (unit -> 'a parser) -> 'a parser

  (* ---- character primitives ------------------------------------------ *)
  val anyChar : char parser
  val char    : char -> char parser
  (* Match an exact string. Atomic: on a partial match it fails WITHOUT
     consuming input, so a surrounding `<|>` can still try alternatives. *)
  val string  : string -> string parser
  val oneOf   : string -> char parser
  val noneOf  : string -> char parser
  val digit   : char parser
  val letter  : char parser
  val spaces  : unit parser

  (* Lexeme helper: parse `p` then skip trailing whitespace. *)
  val token   : 'a parser -> 'a parser

  (* Parse a (possibly signed) integer. *)
  val integer : int parser
end
