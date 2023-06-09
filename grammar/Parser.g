include "Lexer.g"

unit: 
  importStmt* topStmt*;

importName: name ("as" name)?;

importStmt: 
  "import" importName ("," importName)* "from" STRING_LIT
| "import" "*" ("as" name)? "from" STRING_LIT;

name: IDENT;

topStmt:
  stmt | methodDecl | typeDecl | enumDecl;

enumDecl:
  "enum" name generic? "{" enumEntry ("," enumEntry)* "}";

enumEntry: name | namedEnumEntry | valuedEnumEntry;

namedEnumEntry: name "{" param ("," param)* "}";

valuedEnumEntry: "(" type ("," type)* ")";

type: qname generic? arraySuffix?
        | prim arraySuffix?;


generic: "<" type ("," type)* ">";

arraySuffix: ("[" expr? "]")+;

prim: "int" | "long" | "byte" | "char" | "short" | "float" | "double" | "i8" | "i16" | "i32" | "i64" | u8 u16 u32 u64;

refType: name generic? ("::" name generic?)*;

typeDecl:
  ("class" | "interface") name generic? "{" classMember* "}";

classMember:
  field | methodDecl | typeDecl | enumDecl;

field:
  name ":" type ("=" expr)?;

methodDecl:
  "func" name generic? "(" params* ")" block;

params: param ("," param)*;

param:
  name ":" type ("?" | "=" expr)?;

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
  "for" "(" "let" name ":" expr ")" stmt;  

//expressions-----------------------------------------------
varDecl:
  "let" varDeclFrag ("," varDeclFrag)*;

varDeclFrag:
  name ("=" expr | "?")?;
  

expr: "import";

/*
expr:
"(" expr ")" | literal | "[" expr*"]" | "new" obj | obj |
 prim "::" name (generics? "(" args? ")")? |
 name |
 name generics "::" name
 name generics "(" args ")"
 name "(" args? ")" |
 name "::" name "(" args ")")?
| expr ("." IDENT (generics? "(" args? ")")? |
 "[" expr (".." expr)? "]")*
| ("*" | "&") expr
| expr "as" type
| expr ("++" | "--") #post
| ("+" | "-" | "++" | "--" | "!" | "~") expr #unary
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
;*/

PRIM: literal | refType | "(" expr ")" | methodCall;

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