#pragma once

#include "Ast.h"
#include "Util.h"

class Parser;

Type *parseType(Parser *p);
VarDecl *varDecl(Parser *p, Type *type, RefType *nm);
VarDecl *varDecl(Parser *p);
RefType *refType(Parser *p);

Expression *parseExpr(Parser *p);
bool isType(Parser *p);
std::vector<Expression *> exprList(Parser *p);