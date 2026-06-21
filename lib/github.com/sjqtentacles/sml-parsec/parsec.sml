(* parsec.sml

   Implementation of the PARSEC signature.

   Representation. Input is the whole string plus a position record. A parser is
   a function from state to an outcome that records, in addition to success or
   failure, whether any input was *consumed*. The consumed flag is what gives
   `<|>` its ordered, non-backtracking semantics:

     - p <|> q : if p fails WITHOUT consuming, try q; if p fails having consumed,
       propagate p's failure (commit). `try p` resets p's consumed flag on
       failure so the surrounding `<|>` can still recover.

   Errors carry the furthest position reached and the set of expected tokens, so
   messages point at the real problem rather than the start of the alternative. *)

structure Parsec :> PARSEC =
struct
  (* Declaring infix INSIDE the structure is required, otherwise `fun p >>= f`
     parses as application rather than an infix definition. *)
  infix 1 >>= >>
  infix 1 <*
  infix 4 <*> <$>
  infixr 1 <|>
  infix 0 <?>

  type pos = { line : int, col : int, off : int }
  type error = { pos : pos, expected : string list, msg : string option }
  datatype 'a result = Ok of 'a | Err of error

  type state = { src : string, pos : pos }

  (* consumed flag, then either value+state or error *)
  datatype 'a reply = OkR of 'a * state | ErrR of error
  datatype 'a outcome = Consumed of 'a reply | Empty of 'a reply

  type 'a parser = state -> 'a outcome

  val startPos : pos = { line = 1, col = 1, off = 0 }

  fun mkErr (p : pos) (exp : string list) (m : string option) : error =
      { pos = p, expected = exp, msg = m }

  (* Merge two errors, keeping the one that reached further; union expected
     sets when they are at the same position. *)
  fun mergeErr (e1 : error) (e2 : error) : error =
      let val o1 = #off (#pos e1) and o2 = #off (#pos e2)
      in if o1 > o2 then e1
         else if o2 > o1 then e2
         else { pos = #pos e1,
                expected = (#expected e1) @ (#expected e2),
                msg = case #msg e1 of SOME _ => #msg e1 | NONE => #msg e2 }
      end

  (* advance a position over a single character *)
  fun bump ({line, col, off} : pos) c =
      if c = #"\n" then { line = line + 1, col = 1, off = off + 1 }
      else { line = line, col = col + 1, off = off + 1 }

  fun return x = fn s => Empty (OkR (x, s))

  fun fail m = fn (s : state) =>
      Empty (ErrR (mkErr (#pos s) [] (SOME m)))

  fun p >>= f = fn s =>
      (case p s of
           Empty (OkR (a, s')) => f a s'
         | Empty (ErrR e) => Empty (ErrR e)
         | Consumed (OkR (a, s')) =>
             (* once consumed, stay consumed regardless of f's empty/consumed *)
             (case f a s' of
                  Empty r => Consumed r
                | Consumed r => Consumed r)
         | Consumed (ErrR e) => Consumed (ErrR e))

  fun p >> q = p >>= (fn _ => q)
  fun p <* q = p >>= (fn a => q >>= (fn _ => return a))
  fun pf <*> px = pf >>= (fn f => px >>= (fn x => return (f x)))
  fun f <$> px = px >>= (fn x => return (f x))

  fun p <|> q = fn s =>
      (case p s of
           Empty (ErrR e1) =>
             (case q s of
                  Empty (ErrR e2) => Empty (ErrR (mergeErr e1 e2))
                | Empty (OkR (a, s')) => Empty (OkR (a, s'))
                | other => other)
         | Empty (OkR (a, s')) => Empty (OkR (a, s'))
         | consumed => consumed)

  fun try p = fn s =>
      (case p s of
           Consumed (ErrR e) => Empty (ErrR e)  (* pretend nothing consumed *)
         | other => other)

  fun p <?> name = fn s =>
      (case p s of
           Empty (ErrR e) =>
             Empty (ErrR { pos = #pos e, expected = [name], msg = #msg e })
         | other => other)

  (* ---- primitives ---- *)

  fun anyChar (s : state) =
      let val { src, pos } = s
          val off = #off pos
      in if off < String.size src
         then let val c = String.sub (src, off)
              in Consumed (OkR (c, { src = src, pos = bump pos c })) end
         else Empty (ErrR (mkErr pos ["any character"] NONE))
      end

  fun sat pred = fn (s : state) =>
      let val { src, pos } = s
          val off = #off pos
      in if off < String.size src
         then let val c = String.sub (src, off)
              in if pred c
                 then Consumed (OkR (c, { src = src, pos = bump pos c }))
                 else Empty (ErrR (mkErr pos [] NONE))
              end
         else Empty (ErrR (mkErr pos ["more input"] NONE))
      end

  fun char c = (sat (fn x => x = c)) <?> ("'" ^ str c ^ "'")

  fun oneOf set = sat (fn c => CharVector.exists (fn x => x = c) set)
  fun noneOf set = sat (fn c => not (CharVector.exists (fn x => x = c) set))

  val digit = (sat Char.isDigit) <?> "digit"
  val letter = (sat Char.isAlpha) <?> "letter"

  fun string str = fn (s : state) =>
      let val { src, pos } = s
          val n = String.size str
          val off = #off pos
      in if off + n <= String.size src
            andalso String.substring (src, off, n) = str
         then let
                fun adv (i, p) = if i >= n then p
                                 else adv (i + 1, bump p (String.sub (str, i)))
                val pos' = adv (0, pos)
              in if n = 0 then Empty (OkR (str, { src = src, pos = pos' }))
                 else Consumed (OkR (str, { src = src, pos = pos' }))
              end
         else Empty (ErrR (mkErr pos ["\"" ^ str ^ "\""] NONE))
      end

  (* ---- many / repetition (iterative so deep inputs don't overflow) ---- *)

  fun many p = fn s =>
      let
        fun loop (acc, st, consumedAny) =
            (case p st of
                 Empty (OkR _) =>
                   (* a parser that succeeds without consuming would loop
                      forever; treat as done to stay total *)
                   finish (acc, st, consumedAny)
               | Empty (ErrR _) => finish (acc, st, consumedAny)
               | Consumed (OkR (a, st')) => loop (a :: acc, st', true)
               | Consumed (ErrR e) => Consumed (ErrR e))
        and finish (acc, st, consumedAny) =
            let val r = OkR (List.rev acc, st)
            in if consumedAny then Consumed r else Empty r end
      in loop ([], s, false) end

  fun many1 p = p >>= (fn x => many p >>= (fn xs => return (x :: xs)))

  fun optional p =
      (p >>= (fn x => return (SOME x))) <|> return NONE

  fun sepBy1 p sep =
      p >>= (fn x =>
        many (sep >> p) >>= (fn xs => return (x :: xs)))

  fun sepBy p sep =
      sepBy1 p sep <|> return []

  fun between openp closep p =
      openp >> (p <* closep)

  fun chainl1 p opp =
      let
        fun rest x =
            (opp >>= (fn f => p >>= (fn y => rest (f (x, y)))))
            <|> return x
      in p >>= (fn x => rest x) end

  val spaces = many (sat Char.isSpace) >>= (fn _ => return ())

  fun token p = p <* spaces

  fun delay thunk = fn s => (thunk ()) s

  fun eof (s : state) =
      if #off (#pos s) >= String.size (#src s)
      then Empty (OkR ((), s))
      else Empty (ErrR (mkErr (#pos s) ["end of input"] NONE))

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

  (* ---- driver ---- *)

  fun runParser p src =
      let val s0 = { src = src, pos = startPos }
      in case p s0 of
             Empty (OkR (a, _)) => Ok a
           | Consumed (OkR (a, _)) => Ok a
           | Empty (ErrR e) => Err e
           | Consumed (ErrR e) => Err e
      end

  fun errorToString (e : error) =
      let
        val { line, col, ... } = #pos e
        val loc = "line " ^ Int.toString line ^ ", column " ^ Int.toString col
        val what =
            case #msg e of
                SOME m => m
              | NONE =>
                  (case #expected e of
                       [] => "unexpected input"
                     | xs => "expected " ^ String.concatWith " or " xs)
      in "parse error at " ^ loc ^ ": " ^ what end
end
