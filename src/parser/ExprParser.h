#pragma once

#include "Ast.h"
#include "Util.h"

class Parser;

Type *parseType(Parser *p);
RefType *refType(Parser *p);

bool isType(Parser *p);
std::vector<Expression *> exprList(Parser *p);