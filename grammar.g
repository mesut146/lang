unit: 
  importStmt* topStmt*;

importStmt: 
  "import" name ("as" name)?;

name: ident;

//no field bc varDecl is same
topStmt:
  stmt | method | typeDecl | enumDecl;

enumDecl:
  "enum" name "{" name ("," name)* "}";

type:
  prim | qname | generic | "void" | "var" | "let";

prim: "int" | "long" | "byte" | "char" | "short" | "float" | "double" | sizedInt;

refType:
  generic | qname;

generic:
  qname "<" type ("," type)* ">";

typeDecl:
  ("class" | "interface") name (":" refType ("," refType)*)? "{" classMember* "}";

classMember:
  field | method | typeDecl | enumDecl;

method:
  type name "(" param* ")" block;

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

//expressions-----------------------------------------------
varDecl:
  type varDeclFrag+;

varDeclFrag:
  name ("=" expr)?;

expr:
 assign | infix | postfix | prefix | fieldAccess | qname | methodCall | literal | ternary | varDec l creation | arrayAccess;

methodCall:
  (expr ".")? name "(" args? ")";

args:
  expr ("," expr)*;

fieldAccess:
  expr "." name;

assign:
  (qname | fieldAccess ) assignOp  expr;

assignOp: "=" | "+=" |  "-="  |  "*=" |  "/=" | "^=" | "&=" | "|=" | "<<=" | ">>=";

qname: name ( "." name)*;

postfix:
  expr ("++" | "--");

prefix:
  ("++" | "--") expr;

infix:
  expr infixOp expr;

infixOp:
  "+" |  "-" |  "*" | "/" | "^" | "%" | "&" |  "|" | "&&" | "||" | "!=" | "<" | ">" | "<<" | ">>" | "**";

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
  names? "=>" (stmt | expr);
| ( names? ) "==>" (stmt | expr);

array:
  "[" exprs? "]";

arrayAccess:
  expr "[" expr "]";  


  