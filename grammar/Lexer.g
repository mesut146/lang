token {
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
}
token {
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
}
token {
  GT: '>'; // §3.12 Operators
  LT: '<';
  BANG: '!';
  TILDE: '~';
  QUES: '?';
  COLON: ':';
  ARROW: '=>';
  EQEQ: '==';
  LTEQ: '<=';
  GTEQ: '>=';
  NOTEQ: '!=';
  AND: '&&';
  OR: '||';
  INC: '++';
  DEC: '--';
  ADD: '+';
  SUB: '-';
  STAR: '*';
  DIV: '/';
  BITAND: '&';
  BITOR: '|';
  CARET: '^';
  MOD: '%';
  LSHIFT: '<<';
  RSHIFT: '>>';
  STARSTAR: '**';

  ASSIGN: '=';
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
}
token {
  //prim types
  CHAR: 'char';
  BYTE: 'byte';
  SHORT: 'short';
  INT: 'int';
  LONG: 'long';
  FLOAT: 'float';
  DOUBLE: 'double';
  BOOLEAN: 'boolean' | 'bool';
  VOID: 'void';
}

token {
  //literals
  BOOLEAN_LIT: 'true' | 'false';
  NULL_LIT: 'null';
  INTEGER_LIT: [0-9]+;
  FLOAT_LIT: [0-9]+ '.' [0-9]+;
  CHAR_LIT: [:char:];
  STRING_LIT: [:string:];

  IDENT: [a-zA-Z_] [a-zA-Z_0-9]*;
}

skip{
  WS: [ \t\r\n\u000c]+;
  BLOCK_COMMENT: [:block_comment:];
  LINE_COMMENT: [:line_comment:];
}
