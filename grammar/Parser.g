include "Lexer.g"

unit: 
  importStmt* topStmt*;

importStmt: 
  "import" name ("as" name)?;

name: IDENT;

//no field bc varDecl is same
topStmt:
  stmt | methodDecl | typeDecl | enumDecl;

enumDecl:
  "enum" name "{" name ("," name)* "}";

type:
  prim | refType | "void" | "var" | "let";
  
realType:
  prim | refType;

prim: "int" | "long" | "byte" | "char" | "short" | "float" | "double";

refType:
  generic | qname;

generic:
  qname generics;

generics:
  "<" type ("," type)* ">";

typeDecl:
  ("class" | "interface") name generics? (":" refType ("," refType)*)? "{" classMember* "}";

classMember:
  field | methodDecl | typeDecl | enumDecl;

field:
  varDecl ";";

methodDecl:
  "fn" name "(" param* ")" ":" type block;

param:
  type name ("?" | "=" expr)?;

//statements-------------------------------------------
block:
  "{" stmt* "}";

stmt:
  ifStmt | whileStmt | forStmt | forEachStmt | exprStmt | varDecl;

exprStmt:
  expr ";";

ifStmt:
  "if" "(" expr ")" stmt ("else" stmt)?;

whileStmt:
  "while" "(" expr ")" stmt;

forStmt:
  "for" "(" varDecl? ";" expr? ";" exprs? ")" stmt;
  
forEachStmt:
  "for" "(" type name ":" expr ")" stmt;  

//expressions-----------------------------------------------
varDecl:
  ("let" | "var") varDeclFrag ("," varDeclFrag)*;

varDeclFrag:
  name (":" realType)? ("=" expr)?;
  
singleVar:
  ("let" | "var") name ":" realType;

expr: PRIM0;

/*
methodCall2: (fieldAccess | arrayAccess) ("." IDENT "(" ")")+;
fieldAccess: (arrayAccess | methodCall2) ("." IDENT)+;
arrayAccess: (arrayAccess | methodCall2) ("[" E "]")+;

expr:
| PRIM ("." IDENT ("(" ")")? | "[" E "]")*
| expr ("++" | "--") #post
| ("+" | "-" | "++" | "--" | "!" | "~" | "(" type ")" expr) expr #unary
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
| expr "?" expr ":" expr %right
| expr ("=" | "+=" | "-=" | "*=" | "/=" | "%=" | "&=" | "^=" | "|=" | "<<=" | ">>=" | ">>>=") expr %right
;*/

PRIM: literal | qname | "(" expr ")" | methodCall;

methodCall: name "(" args? ")";

args:
  expr ("," expr)*;
  
exprs:
  expr ("," expr)*;


qname: name ( "." name)*;


literal:
  STRING_LIT | CHAR_LIT | INTEGER_LIT | FLOAT_LIT | BOOLEAN_LIT | NULL_LIT;

creation:
  type "(" args? ")" | objInit | type objInit;
  
objInit: "{" pair ("," pair)* "}";

pair: name ":" expr;

arrowFunc:
  names? "=>" (stmt | expr)
| "(" names? ")" "=>" (stmt | expr);

names:
  name ("," name)*;

array:
  "[" exprs? "]";



  
