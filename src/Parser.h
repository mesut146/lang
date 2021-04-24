#pragma once

#include "Lexer.h"
#include "Ast.h"
#include <iostream>

class Parser
{
public:
  Lexer lex;
  std::vector<Token*> la;
  int laPos = 0;

  Parser(Lexer& lexer) : lex(lexer) {
    read();
  }

  void read()
  {
    while(1){
      Token* t = lex.next();
      if(t->is(EOF2)) return;
      if (t->is(COMMENT)) continue;
      la.push_back(t);
    }
  }

  Token *pop()
  {
    laPos = 0;
    Token* t = la[0];
    la.erase(la.begin());
    return t;
  }

  //read la without consuming
  Token *peek()
  {
    return la[laPos++];
  }

  Token *consume(TokenType tt)
  {
    Token *t = pop();
    if (t->is(tt))
      return t;
    throw std::string("unexpected token ") + *t->value + " was expecting " + std::to_string(tt);
  }

  std::string* name(){
    return consume(IDENT)->value;
  }
  
  Type type(){
    Token t = *pop();
    Type type;
    type.type = t.value;
    return type;
  }  

  Unit parseUnit();
  Statement* parseStmt();
  ImportStmt parseImport();
  TypeDecl *parseTypeDecl();
  EnumDecl *parseEnumDecl();
};