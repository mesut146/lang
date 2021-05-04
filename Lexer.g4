lexer grammar Lexer;

//keywords
CLASS: 'class';
ENUM: 'enum';
INTERFACE: 'interface';
IMPORT: 'import';
AS: 'as';
BREAK: 'break';
CASE: 'case';
CONTINUE: 'continue';
DO: 'do';
ELSE: 'else';
FOR: 'for';
IF: 'if';
LET: 'let';
RETURN: 'return';
WHILE: 'while';
SWITCH: 'switch';
VAR: 'var';

// §3.11 Separators
LPAREN: '(';
RPAREN: ')';
LBRACE: '{';
RBRACE: '}';
LBRACK: '[';
RBRACK: ']';
SEMI: ';';
COMMA: ',';
DOT: '.';
ELLIPSIS: '...';
AT: '@';
COLONCOLON: '::';

// §3.12 Operators
ASSIGN: '=';
GT: '>';
LT: '<';
BANG: '!';
TILDE: '~';
QUESTION: '?';
COLON: ':';
ARROW: '->';
EQUAL: '==';
LE: '<=';
GE: '>=';
NOTEQUAL: '!=';
AND: '&&';
OR: '||';
INC: '++';
DEC: '--';
ADD: '+';
SUB: '-';
MUL: '*';
DIV: '/';
BITAND: '&';
BITOR: '|';
CARET: '^';
MOD: '%';
//LSHIFT : '<<'; RSHIFT : '>>'; URSHIFT : '>>>';

ADD_ASSIGN: '+=';
SUB_ASSIGN: '-=';
MUL_ASSIGN: '*=';
DIV_ASSIGN: '/=';
AND_ASSIGN: '&=';
OR_ASSIGN: '|=';
XOR_ASSIGN: '^=';
MOD_ASSIGN: '%=';
LSHIFT_ASSIGN: '<<=';
RSHIFT_ASSIGN: '>>=';
URSHIFT_ASSIGN: '>>>=';

//prim types
CHAR: 'char';
BYTE: 'byte';
SHORT: 'short';
INT: 'int';
LONG: 'long';
FLOAT: 'float';
DOUBLE: 'double';
BOOLEAN: 'boolean';

//literals
BOOLEAN_LIT: 'true' | 'false';
NULL_LIT: 'null';
INTEGER_LIT: [0-9]+;
FLOAT_LIT: [0-9]+ '.' [0-9]+;
CHAR_LIT: '\'' .*? '\'';
STRING_LIT: '"' .*? '"';

IDENT: [a-z_] [a-z_0-9]*;

WS: [ \t\r\n\u000C]+ -> skip;
BLOCK_COMMENT: '/*' .*? '*/' -> channel(HIDDEN);
LINE_COMMENT: '//' ~[\r\n]* -> channel(HIDDEN);
