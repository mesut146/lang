parser grammar Parser;
import Lexer;

unit:
  importStmt* topStmt*;

importStmt:
  'import' name ('as' name)?;

name: IDENT;

//no field bc varDecl is same
topStmt:
  stmt | method | typeDecl | enumDecl;

enumDecl:
  'enum' name '{' name (',' name)* '}';

type:
  prim | refType | 'void' | 'var' | 'let';

prim: 'int' | 'long' | 'byte' | 'char' | 'short' | 'float' | 'double';

refType:
  generic | qname;

generic:
  qname generics;

generics:
  '<' type (',' type)* '>';

typeDecl:
  ('class' | 'interface') name generics? (':' refType (',' refType)*)? '{' classMember* '}';

classMember:
  field | method | typeDecl | enumDecl;

field:
  varDecl ';';

method:
  type refType '(' param* ')' block;

param:
  type name ('?' | '=' expr)?;

exprs:
 expr (',' expr)*;

//statements-------------------------------------------
block:
  '{' stmt* '}';

stmt:
  ifStmt | whileStmt | forStmt | forEachStmt | exprStmt | varDecl;

exprStmt:
  expr ';';

ifStmt:
  'if' '(' expr ')' stmt ('else' stmt)?;

whileStmt:
  'while' '(' expr ')' stmt;

forStmt:
  'for' '(' varDecl? ';' expr? ';' exprs? ')' stmt;
forEachStmt:
  'for' '(' varDecl ':' expr ')' stmt;
//expressions-----------------------------------------------
varDecl:
  type varDeclFrag+;

varDeclFrag:
  name ('=' expr)?;

expr:
 assign | infix | postfix | prefix | fieldAccess | qname | methodCall | literal | ternary | varDecl creation | arrayAccess;

methodCall:
  (expr '.')? name '(' args? ')';

args:
  expr (',' expr)*;

fieldAccess:
  expr '.' name;

assign:
  (qname | fieldAccess ) assignOp  expr;

assignOp: '=' | '+=' |  '-='  |  '*=' |  '/=' | '^=' | '&=' | '|=' | '<<=' | '>>=';

qname: name ( '.' name)*;

postfix:
  expr ('++' | '--');

prefix:
  ('++' | '--') expr;

infix:
  expr infixOp expr;

infixOp:
  '+' |  '-' |  '*' | '/' | '^' | '%' | '&' |  '|' | '&&' | '||' | '!=' | '<' | '>' | '<<' | '>>' | '**';

unary:
 ('-' | '!' | '~') expr;

literal:
  STRING_LIT | CHAR_LIT | INTEGER_LIT | FLOAT_LIT;

par:
  '(' expr ')';

ternary:
  expr '?' expr ':' expr;

creation:
  type '(' args ')' | type '{' '}';

array:
  '[' exprs? ']';

arrayAccess:
  expr '[' expr ']';


