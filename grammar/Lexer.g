//The token set of x, mirroring src/ast/lexer.x (names are the TokenType
//entries in src/ast/token.x). Nothing reads this file at build time -- it is
//documentation shipped in the source zip -- so keep it in sync by hand when
//the keyword or operator tables in the lexer change.
//
//Rules that shape the list below:
//  * keywords are looked up only after a whole identifier run, so `iffy` is
//    IDENT and `if` is IF; an identifier starts with a letter or `_` and
//    continues with letters, digits or `_`.
//  * operators/punctuation are matched longest-first (3, then 2, then 1
//    characters) over the table in `make_ops`. `>>`, `>>=`, `<<=`, `%=`, `&=`
//    and `|=` are *not* operators (`<<` and `^=` are; `a >> b` lexes as GT GT
//    and `a <<= 1` as LTLT EQ).
//  * `//` and `/*` are consumed before the operator table, so a DIV only
//    starts when the `/` is not followed by `/` or `*`.
//  * comments are real tokens (COMMENT), not skipped: Parser::fill strips
//    them from the token stream and keeps them for the formatter. `/* */`
//    does not nest and an unclosed one is an error.
//  * TokenType has entries the lexer never emits: VOID (no `void` keyword, so
//    `void` is IDENT), GTGT, LTLTEQ, GTGTEQ, PERCENTEQ, OREQ, ANDEQ (their
//    spellings are not in `make_ops`) and the synthetic EOF_.
token {
  //keywords -- Lexer::make_keywords
  AS: 'as';
  BREAK: 'break';
  CONST: 'const';
  CONTINUE: 'continue';
  DO: 'do';
  ELSE: 'else';
  ENUM: 'enum';
  EXTERN: 'extern';
  FALSE: 'false';
  FOR: 'for';
  FUNC: 'func';
  IF: 'if';
  IMPL: 'impl';
  IMPORT: 'import';
  IS: 'is';
  LET: 'let';
  MATCH: 'match';
  MOD: 'mod';
  NULL_LIT: 'null';
  RETURN: 'return';
  STATIC: 'static';
  STRUCT: 'struct';
  TRAIT: 'trait';
  TRUE: 'true';
  TYPE: 'type';
  VIRTUAL: 'virtual';
  WHILE: 'while';

  //primitive types are keywords too
  BOOLEAN: 'bool';
  F32: 'f32';
  F64: 'f64';
  I8: 'i8';
  I16: 'i16';
  I32: 'i32';
  I64: 'i64';
  U8: 'u8';
  U16: 'u16';
  U32: 'u32';
  U64: 'u64';
}

token {
  //separators / punctuation -- Lexer::make_ops
  LPAREN: '(';
  RPAREN: ')';
  LBRACE: '{';
  RBRACE: '}';
  LBRACKET: '[';
  RBRACKET: ']';
  SEMI: ';';
  COMMA: ',';
  DOT: '.';
  DOTDOT: '..';  //slice range, e.g. a[1..n]
  COLON: ':';
  COLON2: '::';
  HASH: '#';     //attributes, e.g. #derive(..)
  DOLLAR: '$';   //macro metavariables, e.g. $name
}

token {
  //operators -- Lexer::make_ops; the two-character ones are listed first
  //(the lexer tries the longest spelling, so this order is documentation)
  ARROW: '=>';
  EQEQ: '==';
  NOTEQ: '!=';
  LTEQ: '<=';
  GTEQ: '>=';
  ANDAND: '&&';
  OROR: '||';
  PLUSPLUS: '++';
  MINUSMINUS: '--';
  LTLT: '<<';
  PLUSEQ: '+=';
  MINUSEQ: '-=';
  MULEQ: '*=';
  DIVEQ: '/=';
  POWEQ: '^=';

  GT: '>';
  LT: '<';
  BANG: '!';
  TILDE: '~';
  QUES: '?';     //postfix `?`: propagate the error
  EQ: '=';
  PLUS: '+';
  MINUS: '-';
  STAR: '*';
  DIV: '/';
  PERCENT: '%';
  POW: '^';
  AND: '&';
  OR: '|';
}

token {
  //literals -- Lexer::read_number / Lexer::read_string
  //
  //number = '-'? ( '0x' hex+ | [0-9] ('_'? [0-9])* ('.' [0-9]+)? ) suffix?
  //  suffix = '_'? ('i8'|'i16'|'i32'|'i64'|'u8'|'u16'|'u32'|'u64'|'f32'|'f64')
  //A '.' only starts a fraction when a digit follows, so `1.` is INTEGER_LIT
  //DOT and `.5` is DOT INTEGER_LIT. A number with a fraction is FLOAT_LIT,
  //otherwise INTEGER_LIT. Hex takes no `_` separators and no suffix. The
  //suffix needs no `_` (`1i32` is one token) but a bare `1_` is an error. A
  //`-` immediately followed by a digit starts the number, so `-5` and `-2.5`
  //are single literals while `a-1` and `a -1` lex as IDENT INTEGER_LIT(-1)
  //-- write `a - 1` or `a- 1` to subtract.
  INTEGER_LIT: [0-9]+ | '0x' [0-9a-fA-F]+;
  FLOAT_LIT: [0-9]+ '.' [0-9]+;

  //"..." or '...' with the escapes \n \r \t \\ \" \' \0; any other escape
  //and an unterminated literal are rejected. No raw or interpolated
  //strings. The token value is the unescaped text. Nothing checks that a
  //char literal holds exactly one character: 'ab' is one CHAR_LIT.
  STRING_LIT: [:string:];
  CHAR_LIT: [:char:];

  IDENT: [a-zA-Z_] [a-zA-Z_0-9]*;

  //markers included (`//` up to the newline, `/*` through `*/`)
  COMMENT: [:line_comment:] | [:block_comment:];
}

skip {
  //space, tab, CR, LF (CRLF counts one line). Anything else, including a
  //form feed, is an "unexpected char" error.
  WS: [ \t\r\n]+;
}
