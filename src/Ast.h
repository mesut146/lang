#pragma once

#include <vector>
#include <string>
#include "Ast_all.h"

class Expression
{
public:
  virtual std::string print() = 0;
};
class Statement
{
public:
  virtual std::string print() = 0;
};

class Block : public Statement
{
public:
  std::vector<Statement *> list;

  std::string print();
};

class Name : public Expression{
public:
virtual std::string print() = 0;
};

class SimpleName : public Name
{
public:
  std::string *name;

  std::string print();
};

class QName : public Name
{
public:
  Name *scope;
  std::string *name;

  std::string print();
};

class ImportStmt
{
public:
  std::string *file;
  bool isStar;
  std::string *as;
  std::string print();
};

class Type : public Expression{
  public:
  virtual bool isVar(){return false;};
  //virtual bool isTypeVar() = 0;
  virtual bool isPrim(){return false;};
  virtual bool isVoid(){return false;};

  virtual std::string print() = 0;
};

class SimpleType: public Type
{
public:
  std::string *type;
  bool isVar(){
    return *type == "var";
  }
  bool isTypeVar;
  bool isPrim(){
    return *type == "int" ||  *type == "long" ||  *type == "char" ||  *type == "byte" ||
     *type == "short"  || *type == "float" ||  *type == "double";
  }
  bool isVoid(){
    return *type == "void";
  }

  std::string print();
};

class RefType : public Type{
public:
  Name* name;
  std::vector<Type *> typeArgs;
  std::string print();
};

class Field: public VarDecl
{
public:
  Type *type;
  std::string *name;
  Expression *expr;

  std::string print();
};

class Param
{
public:
  Type *type;
  std::string *name;
  bool isOptional;
  Expression *defVal;

  std::string print();
};

class Method
{
public:
  Type *type;
  std::string name;
  std::vector<Param> params;
  Block body;

  std::string print();
};

class Unit
{
public:
  std::vector<ImportStmt> imports;
  std::vector<BaseDecl *> types;
  std::vector<Method> methods;
  std::vector<Statement *> stmts;

  std::string print();
};

class BaseDecl
{
public:
  virtual std::string print() = 0;
};

class TypeDecl : public BaseDecl
{
public:
  std::string *name;
  bool isInterface;
  std::vector<Type*> typeArgs;
  std::vector<Type*> baseTypes; 
  std::vector<VarDecl> fields;
  std::vector<Method> methods;
  std::vector<BaseDecl *> types;

  std::string print();
};

class EnumDecl : public BaseDecl
{
public:
  std::string *name;
  std::vector<std::string> cons;

  std::string print();
};

class Literal : public Expression
{
public:
  std::string val;
  bool isBool;
  bool isInt;
  bool isFloat;
  bool isStr;
  bool isChar;
  std::string print();
};

class NullLit : public Expression
{
public:
  std::string print();
};

class ExprStmt : public Statement
{
public:
  Expression *expr;
  std::string print();
};

class VarDecl : public Expression
{
public:
  Type *type;
  std::string name;
  Expression *right;

  std::string print();
};

class Unary : public Expression
{
public:
  std::string op;
  Expression *expr;

  std::string print();
};

class Infix : public Expression
{
public:
  Expression *left;
  Expression *right;
  std::string op;
};

class Postfix : public Expression
{
public:
  std::string op;
  Expression *expr;

  std::string print();
};

class MethodCall : public Expression
{
public:
  Expression *scope;
  std::string name;
  std::vector<Expression *> args;

  std::string print();
};

class FieldAccess : public Expression
{
public:
  Expression *scope;
  std::string name;

  std::string print();
};

class ParExpr : public Expression{
public:
  Expression* expr;
  std::string print();
};

class IfStmt : public Statement
{
public:
  Expression *expr;
  Statement *thenStmt;
  Statement *elseStmt;

  std::string print();
};

class WhileStmt : public Statement
{
public:
  Expression *expr;
  Statement *body;

  std::string print();
};

class DoWhile : public Statement
{
public:
  Expression *expr;
  Block body;

  std::string print();
};

class ForStmt : public Statement
{
public:
  std::vector<VarDecl> decl;
  Expression *cond;
  std::vector<Expression *> updaters;

  std::string print();
};

class ForEach : public Statement
{
public:
  VarDecl decl;
  Expression *expr;

  std::string print();
};

class SwitchStmt : public Statement
{
public:
  Expression *expr;
  std::vector<Case> cases;

  std::string print();
};

class Case : public Statement
{
public:
  Expression *expr;
  Statement *body; //can be case

  std::string print();
};
