(* Dependency-free test runner for the Parsec structure.
 * Prints one line per assertion and exits non-zero if any assertion fails. *)

(* Consumers must declare infix status for the operator-named values before
 * using them in infix position. These must match the fixities the library
 * uses internally. *)
infix 1 >>= >>
infix 1 <*
infix 4 <*> <$>
infixr 1 <|>
infix 0 <?>

open CharParsec

val passed = ref 0
val failed = ref 0

fun check (name : string) (cond : bool) : unit =
    if cond
    then (passed := !passed + 1; print ("ok   - " ^ name ^ "\n"))
    else (failed := !failed + 1; print ("FAIL - " ^ name ^ "\n"))

fun okEq eq (r, expected) =
    case r of Ok v => eq (v, expected) | Err _ => false

fun isErr r = case r of Err _ => true | Ok _ => false

(* error offset, for position assertions *)
fun errOff r = case r of Err e => SOME (#off (#pos e)) | Ok _ => NONE

(* ---- an arithmetic evaluator built from the combinators ---- *)
(* grammar:  expr = term (('+'|'-') term)* ; term = factor (('*'|'/') factor)*
             factor = integer | '(' expr ')'        (all whitespace-tolerant) *)
fun makeExpr () =
    let
      val addop = token ((char #"+" >> return (op +))
                         <|> (char #"-" >> return (op -)))
      val mulop = token ((char #"*" >> return (op * ))
                         <|> (char #"/" >> return (op div)))
      fun expr () = chainl1 (delay term) addop
      and term () = chainl1 (delay factor) mulop
      and factor () =
            token integer
            <|> between (token (char #"(")) (token (char #")")) (delay expr)
    in
      spaces >> (delay expr <* eof)
    end

(* ---- token-stream demo: a separate parser instance over a token list ----
   `item` is a small datatype standing in for a lexer's output. We reuse the
   exact same combinators (delay/chainl1/between/...) that the char parser uses,
   proving the core is genuinely stream-agnostic. *)
datatype tok = TNum of int | TPlus | TStar | TLParen | TRParen

fun showTok t =
    case t of
        TNum n => Int.toString n
      | TPlus => "+"
      | TStar => "*"
      | TLParen => "("
      | TRParen => ")"

structure TokStream = ListStream (type t = tok val show = showTok)
structure TP = ParsecFn (TokStream)

fun runTokenTests () =
  let
    local
      infix 1 >>= >>
      infix 1 <*
      infix 4 <*> <$>
      infixr 1 <|>
      infix 0 <?>
    in
      open TP
      (* a number token, extracting its int payload *)
      val num = sat (fn TNum _ => true | _ => false)
                >>= (fn TNum n => return n | _ => fail "number")
      val plus = sat (fn TPlus => true | _ => false) >> return (op +)
      val star = sat (fn TStar => true | _ => false) >> return (op * )
      val lpar = sat (fn TLParen => true | _ => false)
      val rpar = sat (fn TRParen => true | _ => false)
      fun expr () = chainl1 (delay term) plus
      and term () = chainl1 (delay factor) star
      and factor () = num <|> between lpar rpar (delay expr)
      val top = delay expr <* eof
      fun runToks ts = TP.runParser top { toks = ts, idx = 0 }
    end
    (* 2 + 3 * 4 = 14 *)
    val () = check "token stream: 2 + 3 * 4 = 14"
                   (case runToks [TNum 2, TPlus, TNum 3, TStar, TNum 4] of
                        TP.Ok n => n = 14 | TP.Err _ => false)
    (* (2 + 3) * 4 = 20 *)
    val () = check "token stream: (2 + 3) * 4 = 20"
                   (case runToks [TLParen, TNum 2, TPlus, TNum 3, TRParen,
                                  TStar, TNum 4] of
                        TP.Ok n => n = 20 | TP.Err _ => false)
    (* a malformed token stream fails *)
    val () = check "token stream: rejects trailing token"
                   (case runToks [TNum 1, TNum 2] of
                        TP.Err _ => true | TP.Ok _ => false)
    (* error position is reported as a token offset *)
    val () = check "token stream: error at token offset 1"
                   (case runToks [TNum 1, TStar, TStar] of
                        TP.Err e => #off (#pos e) = 2 | TP.Ok _ => false)
  in () end

fun run () =
  let
    val pInt = makeExpr ()
    fun evalStr s = runParser pInt s

    (* return / fmap basics *)
    val () = check "return yields value"
                   (okEq (op = : int*int->bool) (runParser (return 7) "", 7))
    val () = check "fmap maps result"
                   (okEq (op =) (runParser ((fn c => Char.ord c) <$> char #"A") "A", 65))

    (* char / string primitives *)
    val () = check "char matches"
                   (okEq (op = : char*char->bool) (runParser (char #"x") "x", #"x"))
    val () = check "char fails on mismatch" (isErr (runParser (char #"x") "y"))
    val () = check "string matches"
                   (okEq (op = : string*string->bool)
                         (runParser (string "let") "let x", "let"))

    (* many / many1 *)
    val () = check "many digits"
                   (okEq (op =) (runParser (implode <$> many digit) "12345", "12345"))
    val () = check "many on empty succeeds with []"
                   (okEq (op =) (runParser (implode <$> many digit) "", ""))
    val () = check "many1 requires at least one" (isErr (runParser (many1 digit) "abc"))

    (* sepBy: comma-separated integers *)
    val csv = sepBy (token integer) (token (char #","))
    val () = check "sepBy parses list"
                   (okEq (op = : int list * int list -> bool)
                         (runParser (spaces >> (csv <* eof)) "1, 2, 3", [1,2,3]))
    val () = check "sepBy parses empty"
                   (okEq (op =) (runParser (spaces >> (csv <* eof)) "", []))

    (* integer with leading sign *)
    val () = check "integer parses negative"
                   (okEq (op =) (runParser integer "~42", ~42))

    (* the arithmetic evaluator: precedence + associativity *)
    val () = check "eval 2+3*4 = 14"
                   (okEq (op =) (evalStr "2+3*4", 14))
    val () = check "eval (2+3)*4 = 20"
                   (okEq (op =) (evalStr "(2+3)*4", 20))
    val () = check "eval left-assoc 10-3-2 = 5"
                   (okEq (op =) (evalStr "10-3-2", 5))
    val () = check "eval whitespace tolerant  ( 1 + 2 ) * 3 = 9"
                   (okEq (op =) (evalStr "  ( 1 + 2 ) * 3 ", 9))
    val () = check "eval nested 2*(3+4*(5-1)) = 38"
                   (okEq (op =) (evalStr "2*(3+4*(5-1))", 38))
    val () = check "eval rejects trailing garbage" (isErr (evalStr "1+2)"))
    val () = check "eval rejects empty" (isErr (evalStr ""))

    (* eof enforcement *)
    val () = check "eof succeeds at end"
                   (okEq (op = : unit*unit->bool) (runParser eof "", ()))
    val () = check "eof fails with leftover" (isErr (runParser eof "x"))

    (* error position: parsing "12+*5" should fail at the '*' (offset 3) *)
    val () = check "error reports furthest position (offset 3 in 12+*5)"
                   (errOff (evalStr "12+*5") = SOME 3)

    (* try / backtracking.
       Our `string` is atomic: it fails without consuming, so `<|>` always
       recovers from it. To demonstrate commit-on-consume we use a parser that
       consumes character-by-character: `char #"l" >> char #"e" >> ...`. *)
    val () = check "atomic string: <|> recovers from failed string"
                   (okEq (op =) (runParser (string "lets" <|> string "letx") "letx", "letx"))

    (* char-sequence commits once it has consumed: matches 'l','e','t' then
       fails at 's' having consumed, so <|> cannot recover. *)
    fun seqStr s =
        let fun go i = if i >= String.size s then return s
                       else char (String.sub (s, i)) >> go (i + 1)
        in go 0 end
    val committed = seqStr "lets" <|> seqStr "letx"
    val () = check "consumed failure commits (no recovery)"
                   (isErr (runParser committed "letx"))
    val () = check "try restores recovery after consumed failure"
                   (okEq (op =) (runParser (try (seqStr "lets") <|> seqStr "letx") "letx",
                                 "letx"))

    (* <?> labels override expected set *)
    val labeled = (digit <?> "a number") 
    val () = check "label appears in error"
                   (case runParser labeled "x" of
                        Err e => List.exists (fn s => s = "a number") (#expected e)
                      | Ok _ => false)

    (* between *)
    val bracketed = between (char #"[") (char #"]") (many1 letter)
    val () = check "between brackets"
                   (okEq (op =) (runParser (implode <$> bracketed) "[abc]", "abc"))

    (* a small consistency batch over the evaluator *)
    val cases = [("7", 7), ("1+1", 2), ("100", 100), ("2*3+4*5", 26),
                 ("((1))", 1), ("8/2/2", 2), ("1+2+3+4+5", 15)]
    val allOk = List.all (fn (s, v) => okEq (op =) (evalStr s, v)) cases
    val () = check "all evaluator sample cases" allOk

    (* ---- token-stream payoff: same combinators over a token list ----
       Demonstrates that the generic core works over a non-char stream. A tiny
       lexer-output token type is parsed with a separate TokenParsec instance.  *)
    val () = runTokenTests ()
  in
    print ("\n" ^ Int.toString (!passed) ^ " passed, "
           ^ Int.toString (!failed) ^ " failed\n");
    OS.Process.exit (if !failed = 0 then OS.Process.success else OS.Process.failure)
  end

val () = run ()
