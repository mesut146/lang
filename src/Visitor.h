#ifndef LANG_VISITOR_H
#define LANG_VISITOR_H

class Visitor {

  virtual void visitExpr(Expr *) = 0;

  virtual void visitStmt(Stmt *) = 0;
};


#endif//LANG_VISITOR_H
