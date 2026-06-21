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
    (* new combinators are stream-generic: choice + chainr1 over tokens.
       Build a right-associative '+' fold to contrast with the left-assoc expr
       grammar above, and use choice to pick a number-or-paren atom. *)
    val () =
      let
        local
          infix 1 >>= >>
          infix 1 <*
          infixr 1 <|>
        in
          open TP
          val num2 = sat (fn TNum _ => true | _ => false)
                     >>= (fn TNum n => return n | _ => fail "number")
          val lpar2 = sat (fn TLParen => true | _ => false)
          val rpar2 = sat (fn TRParen => true | _ => false)
          (* choice over a singleton + paren atom *)
          fun atom () = choice [num2, between lpar2 rpar2 (delay rexpr)]
          (* right-associative subtraction via chainr1: 10-(3-2) style.
             We reuse TPlus as the operator token but fold right. *)
          and rexpr () =
            chainr1 (delay atom)
                    (sat (fn TPlus => true | _ => false) >> return (op -))
          val rtop = delay rexpr <* eof
          fun runR ts = TP.runParser rtop { toks = ts, idx = 0 }
        end
        (* 10 - 3 - 2 folded RIGHT = 10 - (3 - 2) = 9 *)
        val () = check "token stream: chainr1 right-assoc (10-3-2 = 9)"
                       (case runR [TNum 10, TPlus, TNum 3, TPlus, TNum 2] of
                            TP.Ok n => n = 9 | TP.Err _ => false)
        (* choice falls through to the paren atom *)
        val () = check "token stream: choice picks paren atom"
                       (case runR [TLParen, TNum 7, TRParen] of
                            TP.Ok n => n = 7 | TP.Err _ => false)
      in () end
  in () end

(* ---- new combinator vocabulary tests ----
   Exercises choice, chainr1, chainl/chainr, count, manyTill, notFollowedBy,
   endBy/sepEndBy, skipMany/skipMany1, and option. All built on the generic
   core, so they are available through CharParsec. *)
fun runCombinatorTests () =
  let
    (* choice: first matching alternative wins *)
    val abc = choice [char #"a", char #"b", char #"c"]
    val () = check "choice picks a match"
                   (okEq (op = : char*char->bool) (runParser abc "b", #"b"))
    val () = check "choice fails when none match" (isErr (runParser abc "z"))

    (* chainr1: right-associative exponentiation 2^3^2 = 2^(3^2) = 512 *)
    val powop = token (char #"^") >> return (fn (a, b) => Int.toString
                  (Real.round (Math.pow (real (valOf (Int.fromString a)),
                                         real (valOf (Int.fromString b))))))
    val powexpr = spaces >> (chainr1 (token (implode <$> many1 digit)) powop <* eof)
    val () = check "chainr1 is right-associative (2^3^2 = 512)"
                   (okEq (op = : string*string->bool) (runParser powexpr "2^3^2", "512"))

    (* chainl/chainr: zero-or-more chaining with a default *)
    val sumc = chainl (token integer) (token (char #"+") >> return (op +)) 0
    val () = check "chainl folds left with default"
                   (okEq (op =) (runParser (spaces >> (sumc <* eof)) "1+2+3", 6))
    val () = check "chainl returns default on empty"
                   (okEq (op =) (runParser (spaces >> (sumc <* eof)) "", 0))
    val subr = chainr (token integer) (token (char #"-") >> return (op -)) 0
    val () = check "chainr folds right (1-2-3 = 2)"
                   (okEq (op =) (runParser (spaces >> (subr <* eof)) "1-2-3", 2))

    (* count: exactly n *)
    val () = check "count parses exactly 3"
                   (okEq (op =) (runParser (implode <$> count 3 digit) "12345", "123"))
    val () = check "count fails when too few" (isErr (runParser (count 3 digit) "12"))

    (* manyTill: a line comment "//...\n" *)
    val comment = string "//" >> manyTill anyChar (char #"\n")
    val () = check "manyTill stops at terminator"
                   (okEq (op =) (runParser (implode <$> comment) "//hi\nrest", "hi"))

    (* notFollowedBy: never consumes; succeeds when p fails *)
    val () = check "notFollowedBy succeeds when p absent"
                   (okEq (op = : unit*unit->bool)
                         (runParser (notFollowedBy digit) "abc", ()))
    val () = check "notFollowedBy fails when p present"
                   (isErr (runParser (notFollowedBy digit) "1bc"))
    (* must not consume: digit still matches after notFollowedBy letter *)
    val () = check "notFollowedBy does not consume"
                   (okEq (op = : char*char->bool)
                         (runParser (notFollowedBy letter >> digit) "1", #"1"))

    (* endBy / sepEndBy: semicolon-terminated items *)
    val ints = endBy (token integer) (token (char #";"))
    val () = check "endBy requires trailing separator"
                   (okEq (op = : int list*int list->bool)
                         (runParser (spaces >> (ints <* eof)) "1;2;3;", [1,2,3]))
    val intsE = sepEndBy (token integer) (token (char #";"))
    val () = check "sepEndBy allows optional trailing separator"
                   (okEq (op =) (runParser (spaces >> (intsE <* eof)) "1;2;3", [1,2,3]))
    val () = check "sepEndBy with trailing separator"
                   (okEq (op =) (runParser (spaces >> (intsE <* eof)) "1;2;3;", [1,2,3]))

    (* skipMany / skipMany1 *)
    val () = check "skipMany consumes zero or more"
                   (okEq (op = : char*char->bool)
                         (runParser (skipMany (char #" ") >> char #"x") "   x", #"x"))
    val () = check "skipMany1 requires at least one"
                   (isErr (runParser (skipMany1 (char #" ") >> char #"x") "x"))

    (* option: default when p does not match *)
    val () = check "option supplies default"
                   (okEq (op =) (runParser (option 99 integer) "abc", 99))
    val () = check "option uses parsed value"
                   (okEq (op =) (runParser (option 99 integer) "7", 7))
  in () end

(* ---- zero-fixity ergonomics: a grammar written with ONLY named aliases ----
   No `infix` declarations are in scope inside this function; every combinator
   is the curried, prefix-named form (andThen/seqRight/seqLeft/ap/map/orElse/
   label). Proves a consumer can avoid fixity declarations entirely. *)
fun runAliasTests () =
  let
    (* a signed integer, then end-of-input, all without operators *)
    val signedInt =
        orElse (seqRight (char #"~") (map (fn n => ~n) integer))
               integer
    val full = seqLeft (seqRight spaces signedInt) eof
    val () = check "alias: map negates"
                   (okEq (op =) (runParser full "~5", ~5))
    val () = check "alias: orElse falls through"
                   (okEq (op =) (runParser full "5", 5))

    (* andThen (bind) + return-style via map *)
    val twoDigits =
        andThen digit (fn a =>
          andThen digit (fn b =>
            return (Char.ord a * 100 + Char.ord b)))
    val () = check "alias: andThen sequences"
                   (okEq (op =) (runParser twoDigits "12",
                                 Char.ord #"1" * 100 + Char.ord #"2"))

    (* ap: applicative application, building a pair *)
    val pairP =
        ap (map (fn a => fn b => (a, b)) letter) letter
    val () = check "alias: ap applies"
                   (okEq (fn ((a,b),(c,d)) => a=c andalso b=d)
                         (runParser pairP "xy", (#"x", #"y")))

    (* label: override the expected set, prefix form *)
    val labeled = label digit "a number"
    val () = check "alias: label sets expected"
                   (case runParser labeled "q" of
                        Err e => List.exists (fn s => s = "a number") (#expected e)
                      | Ok _ => false)
  in () end

(* ---- lexer / token kit + parse driver tests ---- *)
fun runLexerTests () =
  let
    (* symbol: matches the literal and eats trailing whitespace *)
    val () = check "symbol matches and skips trailing space"
                   (okEq (op = : string*string->bool)
                         (runParser (symbol "let" >> symbol "x") "let   x  ", "x"))

    (* parens around an integer *)
    val () = check "parens wraps a parser"
                   (okEq (op =) (runParser (parens (token integer)) "( 42 )", 42))
    val () = check "brackets wraps a parser"
                   (okEq (op =) (runParser (brackets (token integer)) "[7]", 7))

    (* identifier: first alpha, rest alnum *)
    val ident = identifier Char.isAlpha Char.isAlphaNum
    val () = check "identifier parses alnum word"
                   (okEq (op =) (runParser ident "foo123 bar", "foo123"))
    val () = check "identifier rejects leading digit" (isErr (runParser ident "1foo"))

    (* keyword: a symbol not followed by an identifier char *)
    val () = check "keyword 'let' matches"
                   (okEq (op = : unit*unit->bool) (runParser (keyword "let") "let ", ()))
    val () = check "keyword 'let' rejects 'lettuce'"
                   (isErr (runParser (keyword "let") "lettuce"))

    (* commaSep *)
    val () = check "commaSep parses list"
                   (okEq (op = : int list*int list->bool)
                         (runParser (commaSep (token integer)) "1, 2, 3", [1,2,3]))
    val () = check "commaSep parses empty"
                   (okEq (op =) (runParser (commaSep (token integer)) "", []))

    (* parse driver: requires full input (unlike runParser) *)
    val () = check "parse consumes leading space and requires eof"
                   (okEq (op =) (parse integer "  42", 42))
    val () = check "parse rejects trailing input that runParser allows"
                   (isErr (parse integer "42 rest"))
    val () = check "runParser still allows trailing input"
                   (okEq (op =) (runParser integer "42rest", 42))

    (* lexeme is the new name for token; token kept as alias *)
    val () = check "lexeme behaves like token"
                   (okEq (op =) (runParser (lexeme integer >> lexeme integer) "1 2", 2))
  in () end

(* ---- buildExpressionParser tests ----
   Re-derive the arithmetic evaluator from a precedence table and check it
   matches the hand-rolled makeExpr, then add a right-associative power operator
   and a prefix negation. CharExpr.parser unifies with CharParsec.parser. *)
fun runExprTests () =
  let
    open CharExpr  (* assoc + operator constructors + buildExpressionParser *)
    (* factor: an integer or a parenthesised expression. Tie the knot with
       delay since exprP is recursive through the table. *)
    fun mulop () = lexeme (char #"*") >> return (op * )
    fun divop () = lexeme (char #"/") >> return (op div)
    fun addop () = lexeme (char #"+") >> return (op +)
    fun subop () = lexeme (char #"-") >> return (op -)
    fun table () =
        [ [ Infix (mulop (), LeftAssoc), Infix (divop (), LeftAssoc) ],
          [ Infix (addop (), LeftAssoc), Infix (subop (), LeftAssoc) ] ]
    fun factor () =
        lexeme integer
        <|> parens (delay exprP)
    and exprP () = buildExpressionParser (table ()) (delay factor)
    val full = spaces >> (delay exprP <* eof)
    fun evalE s = runParser full s

    val () = check "expr builder: 2+3*4 = 14" (okEq (op =) (evalE "2+3*4", 14))
    val () = check "expr builder: (2+3)*4 = 20" (okEq (op =) (evalE "(2+3)*4", 20))
    val () = check "expr builder: left-assoc 10-3-2 = 5" (okEq (op =) (evalE "10-3-2", 5))
    val () = check "expr builder: 8/2/2 = 2" (okEq (op =) (evalE "8/2/2", 2))
    (* match the hand-rolled evaluator on the existing sample batch *)
    val cases = [("7", 7), ("1+1", 2), ("100", 100), ("2*3+4*5", 26),
                 ("((1))", 1), ("8/2/2", 2), ("1+2+3+4+5", 15)]
    val () = check "expr builder: matches makeExpr on sample batch"
                   (List.all (fn (s, v) => okEq (op =) (evalE s, v)) cases)

    (* right-associative power: 2^3^2 = 2^(3^2) = 512 *)
    fun powop () = lexeme (char #"^") >> return (fn (a, b) =>
                     Real.round (Math.pow (real a, real b)))
    fun ptable () = [ [ Infix (powop (), RightAssoc) ] ]
    fun pfactor () = lexeme integer <|> parens (delay ppow)
    and ppow () = buildExpressionParser (ptable ()) (delay pfactor)
    val () = check "expr builder: right-assoc 2^3^2 = 512"
                   (okEq (op =) (runParser (spaces >> (delay ppow <* eof)) "2^3^2", 512))

    (* prefix negation: -(3) and chained --3 *)
    fun negop () = lexeme (char #"-") >> return (fn x => ~x)
    fun ntable () = [ [ Prefix (negop ()) ] ]
    fun nfactor () = lexeme integer <|> parens (delay nexpr)
    and nexpr () = buildExpressionParser (ntable ()) (delay nfactor)
    val () = check "expr builder: prefix negation -5 = ~5"
                   (okEq (op =) (runParser (spaces >> (delay nexpr <* eof)) "-5", ~5))
    val () = check "expr builder: chained prefix --5 = 5"
                   (okEq (op =) (runParser (spaces >> (delay nexpr <* eof)) "--5", 5))
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
    val () = runCombinatorTests ()
    val () = runAliasTests ()
    val () = runLexerTests ()
    val () = runExprTests ()
  in
    print ("\n" ^ Int.toString (!passed) ^ " passed, "
           ^ Int.toString (!failed) ^ " failed\n");
    OS.Process.exit (if !failed = 0 then OS.Process.success else OS.Process.failure)
  end

val () = run ()
