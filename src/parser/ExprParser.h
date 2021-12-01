#pragma once

#include "Ast.h"
#include "Util.h"

class Parser;

bool isType(Parser *p);
std::vector<Expression *> exprList(Parser *p);