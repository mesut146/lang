include "Lexer.g";

unit: importStmt* item*;

importStmt: "import" name ("/" name)*;

name: IDENT;

item: global | decl | methodDecl | implDecl | traitDecl | externBlock | constDecl | typeAlias;

global: "static" name (":" type)? "=" expr;

decl: structDecl | enumDecl;
structDecl: "struct" type "{" field* "}";
field: name ":" type;
enumDecl: "enum" type "{" enumVariant ("," enumVariant)* "}";
enumVariant: name "(" field ("," field)* ")";

type: prim_type | arrayType | sliceType | refType;
prim_type: "i8" | "i16" | "i32" | "i64" | "u8" | "u16" | "u32" | "u64";
arrayType: "[" type ";" INTEGER_LIT "]";
sliceType: "[" type "]";
refType: name generics? ("::" name generics?)*;
generics: "<" type ("," type)* ">";


methodDecl:
  "func" name generics? "(" (name ","?)? params* ")" (":" type)? block;

params: param ("," param)*;

param:
  name ":" type ("?" | "=" expr)?;

//statements-------------------------------------------
block:
  "{" stmt* expr? "}";

stmt:
  whileStmt | forStmt | forEachStmt | exprStmt | varDecl | returnStmt | continueStmt | breakStmt;

exprStmt:
  expr ";";

whileStmt:
  "while" "(" expr ")" stmt;

forStmt:
  "for" "(" varDecl? ";" expr? ";" exprs? ")" stmt;
exprs:
  expr ("," expr)*;  
  
forEachStmt:
  "for" "(" "let" name ":" expr ")" stmt;  

//expressions-----------------------------------------------
varDecl:
  "let" varDeclFrag ("," varDeclFrag)*;

varDeclFrag:
  name ("=" expr | "?")?;
  


tuple_or_paren: "(" expr ")" #paren
  | "(" ")" #unit
  | "(" expr "," ")" #single
  | "(" expr ("," expr)+ ","? ")" #multi
;

lambda: "|" lambda_args? "|" (":" type)? (stmt | expr);
lambda_args: name (":" type)? ("," name (":" type)?)*;

prim: 
    literal
  | lambda
  | "func" "(" (type ("," type)*)? ")"
  | match_expr | if_expr | iflet_expr | block_expr
  | tuple_or_paren
  | "[" expr* "]" #array
  | ("+" | "-" | "++" | "--" | "!" | "*" | "&") expr #unary
  | methodCall | macroCall | type | name
;

prim_name: type (callTail | "!" callTail)?;

methodCall: expr "." name generics? callTail;
callTail: "(" args? ")";
args: expr ("," expr)*;

macroCall: type "." name callTail;

prim2: res=prim res=obj(res) ("." INTEGER_LIT | "." IDENT | "." IDENT callTail | "[" expr (".." expr)? "]" | "?")*;

expr:
| prim2 "as" type | prim2 "is" prim2
| expr ("*" | "/" | "%") expr %left
| expr ("+" | "-") expr %left
| expr ("<<" | ">" ">" | ">" ">" ">") expr %left
| expr ("<" | ">" | "<=" | ">=") expr %left
| expr ("==" | "!=") expr
| expr "&" expr %left
| expr "^" expr %left
| expr "|" expr %left
| expr "&&" expr %left
| expr "||" expr %left
| expr ("=" | "+=" | "-=" | "*=" | "/=" | "%=" | "&=" | "^=" | "|=" | "<<=" | ">>=" | ">>>=") expr %rhs
;

literal:
  STRING_LIT | CHAR_LIT | INTEGER_LIT | FLOAT_LIT | BOOLEAN_LIT | NULL_LIT;

creation: objInit | type objInit;
objInit: "{" pair ("," pair)* "}";
pair: name ":" expr;

arrowFunc:
  names? "=>" (stmt | expr)
| "(" names? ")" "=>" (stmt | expr);
names:
  name ("," name)*;


if_expr:
  "if" "(" expr ")" stmt ("else" stmt)?;