#pragma once

#include "Ast.h"

class Visitor {

  virtual void visitExpr(Expr *) = 0;

  virtual void visitStmt(Stmt *) = 0;
};
