#pragma once

#include <string>

enum TokenType
{
  EOF2,
  IDENT,
  CLASS,
  ENUM,
  INTERFACE,
  VOID,
  CHAR,
  BYTE,
  INT,
  LONG,
  FLOAT,
  DOUBLE,
  SHORT,
  BOOLEAN,
  TRUE,
  FALSE,
  NULL_LIT,
  INTEGER_LIT,
  FLOAT_LIT,
  CHAR_LIT,
  STRING_LIT,
  COMMENT,
  IMPORT,
  AS,
  RETURN,
  BREAK,
  CONTINUE,
  FUNC,
  LET,
  VAR,
  IF_KW,
  ELSE_KW,
  FOR,
  WHILE,
  DO,
  SWITCH,
  CASE,
  EQ,
  PLUS,
  MINUS,
  MUL,
  DIV,
  POW,
  PERCENT,
  BANG,
  TILDE,
  QUES,
  SEMI,
  COLON,
  QUOTE1,
  QUOTE2,
  AND,
  OR,
  ANDAND,
  OROR,
  EQEQ,
  PLUSEQ,
  MINUSEQ,
  MULEQ,
  DIVEQ,
  POWEQ,
  PERCENTEQ,
  LTEQ,
  GTEQ,
  LTLTEQ,
  GTGTEQ,
  OREQ,
  ANDEQ,
  LT,
  GT,
  LTLT,
  GTGT,
  COMMA,
  DOT,
  LPAREN,
  RPAREN,
  LBRACKET,
  RBRACKET,
  LBRACE,
  RBRACE
};

class Token
{
public:
  std::string *value;
  TokenType type;
  int start;
  int end;
  Token(TokenType t) : type(t) {}
  Token(TokenType t, std::string s) : type(t), value(new std::string(s)) {}

  bool is(TokenType t)
  {
    return t == type;
  }

  bool is(std::initializer_list<TokenType> t)
  {
    for(TokenType tt:t)
      if(tt == type) return true;
    return false;
  }
};