include "Lexer.g"

unit: 
  importStmt* topStmt*;

importName: name ("as" name)?;

importStmt: 
  "import" importName ("," importName)* "from" STRING_LIT
| "import" "*" ("as" name)? "from" STRING_LIT;

name: IDENT;

//no field bc varDecl is same
topStmt:
  stmt | methodDecl | typeDecl | enumDecl;

enumDecl:
  "enum" name "{" enumEntry ("," enumEntry)* "}";

enumEntry: simpleEnumEntry | namedEnumEntry | valuedEnumEntry;
simpleEnumEntry: name;
namedEnumEntry: name "{" param ("," param)* "}";
valuedEnumEntry: "(" type ("," type)* ")";

type: qname generic? arraySuffix?
        | prim arraySuffix?;

generic: "<" type ("," type)* ">";

arraySuffix: ("[" expr? "]")+;

varType: type | "var" | "let";

prim: "int" | "long" | "byte" | "char" | "short" | "float" | "double";

refType: name generic?;

typeDecl:
  ("class" | "interface") name generics? (":" refType ("," refType)*)? "{" classMember* "}";

classMember:
  field | methodDecl | typeDecl | enumDecl;

field:
  varDecl ";";

methodDecl:
  ("void" | type) name generic? "(" params* ")" block;

params: param ("," param)*;

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
  varType varDeclFrag ("," varDeclFrag)*;

varDeclFrag:
  name ("=" expr | "?")?;
  

expr: "import";

/*
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
| expr "?" expr ":" expr %rhs
| expr ("=" | "+=" | "-=" | "*=" | "/=" | "%=" | "&=" | "^=" | "|=" | "<<=" | ">>=" | ">>>=") expr %rhs
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

methodReference: type "::" name;

xmlElement: "<" name attr* "/" ">"
        |   "<" name attr* ">" xmlElement* | text "<" "/" name ">";
attr: name "=" STRING_LIT;



  
