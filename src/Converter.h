#pragma once

#include <string>
#include "BaseVisitor.h"

class Converter: public BaseVisitor<void*,void*>{
public:
  std::string srcDir;
  std::string outDir;
  std::fstream hs;
  std::fstream ss;
  Unit* unit;

  void convertAll();

  void convert(const std::string& path);

  void header(Unit* unit, const std::string& name);
  void source(Unit* unit, const std::string& name);

  void* visitBlock(Block *, void* arg) override;
  void* visitReturnStmt(ReturnStmt *r, void* arg) override;
  void* visitExprStmt(ExprStmt *r, void* arg) override;
  void* visitAssertStmt(AssertStmt *r, void* arg) override;

  void* visitInfix(Infix *b, void* arg) override;
  void* visitSimpleName(SimpleName*r, void* arg) override;
  void* visitLiteral(Literal *r, void* arg) override;
  void* visitMethodCall(MethodCall *r, void* arg) override;
  void* visitVarDecl(VarDecl* v, void* arg) override;
  void* visitRefExpr(RefExpr* v, void* arg) override;
  void* visitDerefExpr(DerefExpr* v, void* arg) override;
  void* visitParExpr(ParExpr* v, void* arg) override;
  void* visitObjExpr(ObjExpr* v, void* arg) override;
  
};