(* parsecfn.sml

   Implementation of the PARSEC signature as a functor over a STREAM.

   Representation. The parser state is just the input `stream` (the position
   rides inside it, retrieved via `S.pos`). A parser is a function from a stream
   to an outcome that records, in addition to success or failure, whether any
   input was *consumed*. The consumed flag is what gives `<|>` its ordered,
   non-backtracking semantics:

     - p <|> q : if p fails WITHOUT consuming, try q; if p fails having consumed,
       propagate p's failure (commit). `try p` resets p's consumed flag on
       failure so the surrounding `<|>` can still recover.

   Errors carry the furthest position reached (by offset) and the set of
   expected tokens, so messages point at the real problem rather than the start
   of the alternative. Only `anyItem`, `sat`, and `eof` read the stream; every
   other combinator is defined in terms of them and is stream-agnostic. *)

functor ParsecFn (S : STREAM) :> PARSEC
  where type stream = S.stream
  and   type item   = S.item =
struct
  (* Declaring infix INSIDE the structure is required, otherwise `fun p >>= f`
     parses as application rather than an infix definition. *)
  infix 1 >>= >>
  infix 1 <*
  infix 4 <*> <$>
  infixr 1 <|>
  infix 0 <?>

  type stream = S.stream
  type item = S.item

  type pos = { line : int, col : int, off : int }
  type error = { pos : pos, expected : string list, msg : string option }
  datatype 'a result = Ok of 'a | Err of error

  (* The parser state is the stream itself; position is read via S.pos. *)
  type state = S.stream

  (* consumed flag, then either value+state or error *)
  datatype 'a reply = OkR of 'a * state | ErrR of error
  datatype 'a outcome = Consumed of 'a reply | Empty of 'a reply

  type 'a parser = state -> 'a outcome

  fun posOf (s : state) : pos = S.pos s

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

  fun return x = fn s => Empty (OkR (x, s))

  fun fail m = fn (s : state) =>
      Empty (ErrR (mkErr (posOf s) [] (SOME m)))

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

  fun anyItem (s : state) =
      (case S.uncons s of
           SOME (x, s') => Consumed (OkR (x, s'))
         | NONE => Empty (ErrR (mkErr (posOf s) ["any item"] NONE)))

  fun sat pred = fn (s : state) =>
      (case S.uncons s of
           SOME (x, s') =>
             if pred x
             then Consumed (OkR (x, s'))
             else Empty (ErrR (mkErr (posOf s) [] NONE))
         | NONE => Empty (ErrR (mkErr (posOf s) ["more input"] NONE)))

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

  fun delay thunk = fn s => (thunk ()) s

  fun eof (s : state) =
      (case S.uncons s of
           NONE => Empty (OkR ((), s))
         | SOME _ => Empty (ErrR (mkErr (posOf s) ["end of input"] NONE)))

  (* ---- driver ---- *)

  fun runParser p s0 =
      (case p s0 of
           Empty (OkR (a, _)) => Ok a
         | Consumed (OkR (a, _)) => Ok a
         | Empty (ErrR e) => Err e
         | Consumed (ErrR e) => Err e)

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
