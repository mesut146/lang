#pragma once

#include "Lexer.h"
#include "Ast.h"
#include <iostream>

class Parser
{
public:
  Lexer lex;
  std::vector<Token *> la;
  int laPos = 0;

  Parser(Lexer& lexer) : lex(lexer) {}

   //read and set as la
  Token *read()
  {
    Token* t = lex.next();
    if (t->is(COMMENT))
    {
      return read();
    }
    return t;
  }

  void fill(int k){
    int need = k - la.size();
    for(int i = 0; i < need;i++){
      la.push_back(read());
    }
  }

  Token *pop()
  {
    fill(1);
    laPos=0;
    Token* t = la[0];
    la.erase(la.begin());
    return t;
  }

  //read la without consuming
  Token *peek()
  {
    fill(laPos + 1);
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

  Unit parseUnit();
  Statement parseStmt();
  ImportStmt parseImport();
  TypeDecl *parseTypeDecl();
  EnumDecl *parseEnumDecl();
};