include "Lexer.g";

unit: importStmt* item*;

importStmt: "import" name ("/" name)*;

name: IDENT;

item: global | decl | metho | impl | trait | externBlock | constDecl | typeAlias;

global: "static" name (":" type)? "=" expr;

decl: structDecl | enumDecl;
structDecl: "struct" type "{" field* "}";
field: name ":" type;
enumDecl: "enum" type "{" enumVariant ("," enumVariant)* "}";
enumVariant: name "(" field ("," field)* ")";

qname: name ( "." name)*;
type: qname generic? arraySuffix? | prim_type arraySuffix?;
generic: "<" type ("," type)* ">";
arraySuffix: ("[" expr? "]")+;
prim_type: "i8" | "i16" | "i32" | "i64" | "u8" | "u16" | "u32" | "u64";
refType: name generic? ("::" name generic?)*;


methodDecl:
  "func" name generic? "(" (name ","?)? params* ")" (":" type)? block;

params: param ("," param)*;

param:
  name ":" type ("?" | "=" expr)?;

//statements-------------------------------------------
block:
  "{" stmt* expr? "}";

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
;

PRIM: literal | refType | "(" expr ")" | methodCall;

methodCall: name "(" args? ")";

args:
  expr ("," expr)*;
  
exprs:
  expr ("," expr)*;



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