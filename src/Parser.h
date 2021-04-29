#pragma once

#include "Lexer.h"
#include "Ast.h"
#include <iostream>
#include <cstdarg>

class Parser
{
public:
  Lexer lexer;
  std::vector<Token *> tokens;
  int laPos = 0;

  Parser(Lexer &lexer) : lexer(lexer)
  {
    read();
  }

  void reset()
  {
    laPos = 0;
  }

  void read()
  {
    while (1)
    {
      Token *t = lexer.next();
      if (t->is(EOF2))
        return;
      if (t->is(COMMENT))
        continue;
      tokens.push_back(t);
    }
  }

  Token *pop()
  {
    reset();
    Token *t = tokens[0];
    tokens.erase(tokens.begin());
    return t;
  }

  //read a token without consuming
  Token *peek()
  {
    return tokens[laPos++];
  }

  Token *consume(TokenType tt)
  {
    Token *t = pop();
    if (t->is(tt))
      return t;
    throw std::string("unexpected token ") + *t->value + " was expecting " + std::to_string(tt);
  }
  
  bool is(std::initializer_list<TokenType> rest){
    for(TokenType tt:rest){
      if(!peek()->is(tt)) return false;
    }
    return true;
  } 

  std::string *name()
  {
    return consume(IDENT)->value;
  }

  Unit parseUnit();
  Statement *parseStmt();
  Expression* parseExpr();
  TypeDecl *parseTypeDecl();
  EnumDecl *parseEnumDecl();
};