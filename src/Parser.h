#pragma once

#include "Lexer.h"
#include "Ast.h"

class Parser
{
public:
  Lexer lex;
  Token* la;
  
  Parser(Lexer lexer):lex(lexer){}

  Token* next()
  {
    la = lex.next();
    if(la->is(COMMENT)){
    	return next();
    }
    return la;
  }
  
  Token* peek(){
    if(la) return la;
    return next();
  }
  
  Token* consume(TokenType tt){
  	Token* t = peek();
      la = nullptr;
      if(t->is(tt)) return t;
      throw std::string("unexpected") + t->value;
  }

  Unit parseUnit();
  Statement parseStmt();
  ImportStmt parseImport();
  TypeDecl parseTypeDecl();
  EnumDecl parseEnumDecl();
};