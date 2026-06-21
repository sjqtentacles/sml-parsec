(* charparsec.sml

   The CharParsec structure: ParsecFn instantiated at CharStream, re-exported
   with character-specific primitives and a string-based `runParser`.

   The generic core (`>>=`, `<|>`, `many`, `chainl1`, ...) is inherited verbatim
   from the functor result `P`. The character primitives (`char`, `string`,
   `digit`, `integer`, ...) are defined here in terms of `P.sat`/`P.anyItem`. *)

structure CharParsec :> CHAR_PARSEC =
struct
  structure P = ParsecFn (CharStream)

  infix 1 >>= >>
  infix 1 <*
  infix 4 <*> <$>
  infixr 1 <|>
  infix 0 <?>

  open P

  (* Run over a string by constructing the initial CharStream cursor. The
     `stream` type is exposed concretely by CharStream, so we can build it
     directly. *)
  fun runParser p s =
      P.runParser p { src = s, pos = { line = 1, col = 1, off = 0 } }

  (* ---- character primitives ---- *)

  val anyChar = anyItem

  fun char c = (sat (fn x => x = c)) <?> ("'" ^ String.str c ^ "'")

  fun oneOf set = sat (fn c => CharVector.exists (fn x => x = c) set)
  fun noneOf set = sat (fn c => not (CharVector.exists (fn x => x = c) set))

  val digit = (sat Char.isDigit) <?> "digit"
  val letter = (sat Char.isAlpha) <?> "letter"

  (* Match an exact string, atomically. We consume character by character; if
     any character mismatches after some have matched, `try` restores the
     failure to non-consuming so `<|>` can still recover (the original library's
     "string is atomic" guarantee). The empty string succeeds without
     consuming. *)
  fun string str =
      let
        val n = String.size str
        fun go i =
            if i >= n then return str
            else char (String.sub (str, i)) >> go (i + 1)
      in
        if n = 0 then return str
        else (try (go 0)) <?> ("\"" ^ str ^ "\"")
      end

  val spaces = many (sat Char.isSpace) >>= (fn _ => return ())

  fun token p = p <* spaces

  val integer =
      let
        val sign = (char #"~" >> return ~1)
                   <|> (char #"-" >> return ~1)
                   <|> return 1
        val digits = many1 digit
      in
        sign >>= (fn sgn =>
          digits >>= (fn ds =>
            return (sgn * (valOf (Int.fromString (implode ds))))))
      end
end
