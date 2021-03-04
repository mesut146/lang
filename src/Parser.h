#pragma once

#include "Lexer.h"
#include "Ast.h"

class Parser
{
public:
  Lexer lex;

  Token read()
  {
    return lex.next();
  }

  Unit parseUnit();
  Statement parseStmt();
};