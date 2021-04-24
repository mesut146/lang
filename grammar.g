unit: 
  importStmt* topStmt*;

importStmt: 
  "import" name ("as" name)?;

name: ident;

//no field bc varDecl is same
topStmt:
  stmt | method | typeDecl | enumDecl;

enumDecl:
  "enum" name "{" name ("," name)* "}"

type:
  prim | qName | generic | "void" | "var" | "let";

prim: "int" | "long" | "byte" | "char" | "short" | "float" | "double" | sizedInt;

generic:
  qName "<" type ("," type)* ">";

typeDecl:
  ("class" | "interface") name (":" type ("," type)*)? "{" classMember* "}";

classMember:
  field | method | typeDecl | enumDecl;

method:
  type name "(" param* ")" block;

param:
  type name ("?" | "=" expr)?;

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
  "for" "(" varDecl? ";" expr ";" exprs? ")" stmt;

//expr-----------------------------------------------
varDecl:
  type varDeclFrag+;
varDeclFrag:
  name ("=" expr)?;

expr:
 assign | infix | postfix | prefix | fieldAccess | qName | methodCall | literal | ternary | varDec l creation;

methodCall:
  (expr ".")? name "(" args? ")";

args:
  expr ("," expr)*;

fieldAccess:
  expr "." name;

assign:
  (qName | fieldAccess )  ("=" | "+=" |  "-="  |  "*=" |  "/=" | "^=" | "&=" | "|=" | "<<=" | ">>=") expr;

qName: name ( "." name)*;

postfix:
  expr ("++" | "--");

prefix:
  ("++" | "--") expr;

infix:
  expr ("+" |  "-" |  "*" | "/" | "^" | "%" | "&" |  "|" | "&&" | "||" | "!=" | "<" | ">" | "<<" | ">>") expr;

unary:
 ("-" | "!" | "~") expr;

literal:
  str | char | integer | float;

par:
  "(" expr ")";

ternary:
  expr "?" expr ":" expr;

creation:
  type "(" args ")" | type "{" "}";

arrowFunc:
  names? "==>" stmt;


  