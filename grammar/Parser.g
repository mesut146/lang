include "Lexer.g";

//The syntax of x, mirroring src/ast/parser.x. Lexer.g has the tokens, this
//file has the productions. Comments are stripped before parsing
//(Parser::fill), so they may sit between any two tokens. "..." below is the
//token pair DOTDOT DOT.
//
//Name slots:
//  name      Parser::name: IDENT, or one of the keywords `is`, `as`, `type`,
//            `trait`, `mod`.
//  raw_name  a popv() slot: the parser takes any single token's text, so a
//            keyword or literal can spell a function name, struct field,
//            parameter, type, type parameter, import segment, `let` variable
//            or for-each variable.
//  `use`, `macro`, `in` and `_` are not keywords (see Lexer.g): the parser
//  matches those plain IDENTs by text.
//
//Attributes are accepted before any item, but only struct, enum and func
//(and impl/trait/extern members) keep them; the other items parse and drop
//them.

unit: importStmt* item* EOF;

importStmt: "import" raw_name ("/" raw_name)*;
//no trailing ";": `import std/io` is the whole line, and imports may only
//come before the first item of a unit

item: attribute* (
    structDecl | enumDecl | implDecl | traitDecl | methodDecl
  | globalDecl | constDecl | typeAlias | externBlock | modDecl
  | useDecl | macroDecl
  );

attribute: "#" "["? name ("(" expr ("," expr)* ")")? "]"?;

//items--------------------------------------------------------------
structDecl:
  "struct" type (":" type)? (";" | "{" structField* "}"
                             | "(" tupleField ("," tupleField)* ","? ")" ";");
structField: raw_name ":" type ";";    //the last field needs its ";" too
//positional fields: built/read as `T{1, 2}` / `t.0`, no names. The tuple form
//takes no base class (a base would shift every index); the resolver rejects
//the combination when it is written.
tupleField: type;

enumDecl:
  "enum" type (":" type)? "{" (variant ("," variant)* ","?)? "}";
//zero variants is legal: an uninhabited type (`enum Never {}`).
variant:
  name ("(" variantField ("," variantField)* ")"
      | "{" variantField ("," variantField)* "}")?
  ("=" INTEGER_LIT)?;
variantField: raw_name ":" type;

implDecl:
  "impl" typeParams? type ("for" type)? "{" implMember* "}";
traitDecl:
  "trait" type "{" implMember* "}";
implMember: attribute* methodDecl;
typeParams: "<" raw_name ("," raw_name)* ">";

methodDecl:
  "virtual"? "func" raw_name typeParams? "(" params? ")" (":" type)?
  (block | ";");
params:
  "..."
| (selfParam | param) ("," (param | "..."))*;
selfParam: "*"? name;                  //first parameter, in an impl or trait
param: raw_name ":" type;

globalDecl: "static" name (":" type)? ("=" expr)? ";";
//the parser allows a missing initializer, the resolver rejects it
constDecl: "const" name (":" type)? "=" expr ";";
typeAlias: "type" name "=" type ";";

externBlock: "extern" "{" (attribute* (globalDecl | methodDecl))* "}";

modDecl: "mod" name "{" item* "}";
//a module body may hold items, not imports

useDecl: "use" name ("::" name)* ("::" "{" name ("," name)* "}")? ";";
//no trailing comma inside the braces

macroDecl: "macro" name ("(" macroParam (","? macroParam)* ","? ")")? block;
macroParam: name (":" type ("...")?)?;
//the comma between parameters is optional (parse_macro only pops it when it
//is there)

//statements---------------------------------------------------------
block: "{" stmt* blockTail? "}";

blockTail: expr;                       //the block's value: final expression, no ";"

stmt:
  letStmt | returnStmt
| whileStmt | forStmt | forEachStmt
| continueStmt | breakStmt | repeatStmt
| bodyExpr                             //no ";" after if / if let / match / block
| expr ";";                            //expression statement (not a bodyExpr)

bodyExpr: ifExpr | ifLet | matchExpr | block;

body: block | ifLet | ifExpr | stmt;   //Parser::parse_body

letStmt: "let" letFrag ("," letFrag)* ";";
letFrag: raw_name (":" type)? "=" expr;

returnStmt: "return" expr? ";";
whileStmt: "while" "(" expr ")" body;
forStmt: "for" "(" ("let" letFrag ("," letFrag)*)? ";" expr? ";" exprList? ")" body;
forEachStmt: "for" raw_name "in" postfixNoObj block;
continueStmt: "continue" ";";
breakStmt: "break" ";";
repeatStmt: "$" "(" stmt* ")" "*";

ifExpr: "if" "(" expr ")" body ("else" body)?;
ifLet:
  "if" "let" type ("(" bind ("," bind)* ")")? "="
  ("(" expr ")" | postfixNoObj) body ("else" body)?;
bind: name;

matchExpr: "match" postfixNoObj "{" (matchCase ("," matchCase)* ","?)? "}";
//zero cases parse; the resolver insists on a case
matchCase: matchLhs "=>" matchRhs;
matchLhs:
  "_"
| type ("(" (bind ("," bind)* ","?)? ")")?
| type ("|" type)+;
matchRhs: "return" expr ";"? | stmtNoExpr | expr ";"?;
stmtNoExpr:
  letStmt | whileStmt | forStmt | forEachStmt | continueStmt | breakStmt;

lambda:
  "||" (":" type)? lambdaBody
| "|" (lambdaParam ("," lambdaParam)* ","?)? "|" (":" type)? lambdaBody;
lambdaParam: name (":" type)?;
lambdaBody: returnStmt | stmtNoExpr | expr;

//expressions--------------------------------------------------------
//Binding, tighter first: postfix; unary; as/is; * / %; + -; <<; < > <= >=
//(two GT tokens merge into ">>" here); == !=; &; ^; |; &&; ||; assignment.
//Each level folds left, assignment included (`a = b = c` is `(a = b) = c`).
expr: assign;

assign: or (("=" | "+=" | "-=" | "*=" | "/=" | "^=") or)*;
or:     and ("||" and)*;
and:    bitor ("&&" bitor)*;
bitor:  bitxor ("|" bitxor)*;
bitxor: bitand ("^" bitand)*;
bitand: eq ("&" eq)*;
eq:     cmp (("==" | "!=") cmp)*;
cmp:    shift (("<" | ">" | ">" ">" | "<=" | ">=") shift)*;  //">" ">" -> ">>"
shift:  add ("<<" add)*;
add:    mul (("+" | "-") mul)*;
mul:    unary (("*" | "/" | "%") unary)*;
unary:  ("&" | "!" | "-" | "*" | "++" | "--") postfix | asIs;
asIs:   postfix ("as" type)? ("is" postfix)?;

postfix: (prim | objLiteral) postfixOp*;
//an object literal is a type name directly followed by "{"
postfixNoObj: prim postfixOp*;           //match/if let/for-each use prim2(false)
postfixOp:
  "." INTEGER_LIT                        //tuple index
| "." name ("(" exprList? ")")?          //field or method call
| "[" expr (".." expr)? "]"              //index or slice
| "?";                                   //propagate the error

objLiteral: typeRef "{" (entry ("," entry)* ","?)? "}";
entry: name ":" expr | "." expr | expr; //named, base (delegation), positional

prim:
  "$" "(" exprList? ")" (",")? "*"       //repetition; "," is the separator
| "$" name                              //metavariable inside $( ... )*
| literal
| lambda
| "func" "(" (type ("," type)*)? ")" "=>" type
| matchExpr
| block
| ifLet
| ifExpr
| tupleOrParen
| "[" exprList? (";" INTEGER_LIT)? "]"
| ("&" | "!" | "-" | "*" | "++" | "--") postfix
| typeRef ("(" exprList? ")" | "!" "(" exprList? ")")?;
//the "!" call (a macro invocation) takes no type arguments

literal: INTEGER_LIT | FLOAT_LIT | CHAR_LIT | STRING_LIT | "true" | "false";

tupleOrParen:
  "(" ")"
| "(" expr ")"
| "(" expr "," ")"
| "(" expr "," expr ("," expr)* ","? ")";

exprList: expr ("," expr)*;             //may be empty at a call site

//types--------------------------------------------------------------
type:
  "func" "(" (type ("," type)*)? ")" "=>" type
| "(" (type ("," type)* ","?)? ")"
| (arrayType | typeRef) "*"*;

arrayType: "[" type (";" INTEGER_LIT)? "]";   //fixed array or slice
typeRef: simpleType ("::" simpleType)*;
simpleType: raw_name ("<" type ("," type)* ">")?;
//In an expression (`a < b`) the `<...>` is only read as generics when the
//parser's lookahead (isTypeArg) accepts the tokens up to the closing ">".

//Known holes in the current syntax (each is a parse error today):
//  * `let x: T;` -- a `let` always needs "=" expr.
//  * enum tuple variants -- the variant "(" form still parses `name: type`
//    entries, so `A(i32)` does not parse (only tuple *structs* are positional).
//  * `null` -- NULL_LIT is neither isLit nor isName, so it is not usable.
//  * `a %= b`, `a &= b`, `a |= b`, `a <<= b`, `a >>= b` -- get_prec knows
//    PERCENTEQ/ANDEQ/OREQ/LTLTEQ/GTGTEQ, but the lexer never produces those
//    tokens (`%=` is PERCENT EQ, and so on; see Lexer.g).
//  * a ";" after an if / if let / match / block statement in a block.
//  * for-each sources, match scrutinees and if-let values are prim2(false):
//    no binary operator and no object literal. `for x in a + b { }` and
//    `match a + b { }` do not parse.
//  * `x.f<i32>()` -- a postfix `.` call takes no type arguments, so method
//    turbofish does not parse (free functions do: `f<i32>(x)`).
//  * `~` exists as a token but has no unary production.
