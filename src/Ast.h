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

class SimpleName : Expression
{
  public:
  std::string* name;
  
  std::string print();
};

class Name : Expression
{
  public:
  Name *scope;
  std::string* name;
  
  std::string print();
};

class ImportStmt
{
  public:
  
  std::string* file;
  bool isStar;
  std::string *as;
  std::string print();
};

class Type
{
  public:
  std::string* type;
  std::vector<Type*> typeArgs;
  bool isTypeVar;
  bool isPrim;
  bool isVoid;
  
  std::string print();
};

class Field
{
  public:
  Type type;
  std::string* name;
  Expression *expr;
  
  std::string print();
};

class Param
{
  public:
  Type type;
  std::string* name;
  bool isOptional;
  Expression *defVal;
  
  std::string print();
};

class Method
{
  public:
  Type type;
  std::string* name;
  std::vector<Param> params;
  Block* body;
  
  std::string print();
};

class Unit
{
public:
  std::vector<ImportStmt> imports;
  std::vector<BaseDecl*> types;
  std::vector<Method> methods;
  std::vector<Statement*> stmts;
  
  std::string print();
};

class BaseDecl{
  public:
  virtual std::string print() = 0;
};

class TypeDecl : public BaseDecl
{
  public:
  std::string* name;
  bool isInterface;
  std::vector<Type> typeArgs;
  std::vector<Field> fields;
  std::vector<Method> methods;
  std::vector<BaseDecl*> types;
  
  std::string print();
};

class EnumDecl : public BaseDecl
{
public:
  std::string* name;
  std::vector<std::string> cons;
  
  std::string print();
};

class Literal
{
  std::string* val;
  bool isBool;
  bool isInt;
  bool isFloat;
  
  std::string print();
};

class NullLit : Expression
{
  std::string print();
};

class ExprStmt
{
  Expression* expr;
  std::string print();
};


class VarDecl
{
  Type type;
  std::string* name;
  Expression *right;
  
  std::string print();
};

class Unary
{
  std::string op;
  Expression* expr;
  
  std::string print();
};

class Infix
{
  Expression* left;
  Expression* right;
  std::string op;
};

class Postfix
{
  std::string op;
  Expression *expr;
  
  std::string print();
};

class MethodCall
{
  Expression *scope;
  std::string name;
  std::vector<Expression*> args;
  
  std::string print();
};

class FieldAccess
{
  Expression *scope;
  std::string name;
  
  std::string print();
};

class Block
{
public:
  std::vector<Statement*> list;
  
  std::string print();
};

class IfStmt
{
  Expression *expr;
  Statement *thenStmt;
  Statement *elseStmt;
};

class WhileStmt
{
  Expression *expr;
  Statement *body;
};

class DoWhile
{
  Expression *expr;
  Block body;
};

class ForStmt
{
  std::vector<VarDecl> decl;
  Expression *cond;
  std::vector<Expression*> updaters;
};

class ForEach
{
  VarDecl decl;
  Expression *expr;
};

class SwitchStmt
{
  Expression *expr;
  std::vector<Case> cases;
};

class Case : public Statement
{
  Expression* expr;
  Statement *body; //can be case
};