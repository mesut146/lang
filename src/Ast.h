#pragma once

#include <vector>
#include <string>
#include "Ast_all.h"

class Expression
{
};
class Statement
{
};

class SimpleName : Expression
{
  std::string name;
};

class Name : Expression
{
  Name *scope;
  SimpleName name;
};

class ImportStmt
{
  std::string s;
  bool isStar;
  std::string *as;
};

//class,interface,enum
class BaseDecl
{
  std::string name;
};

class Type
{
  std::string type;
  std::vector<Type> typeArgs;
  bool isTypeVar;
};

class Field
{
  Type type;
  std::string name;
  Expression *expr;
};

class Param
{
  Type type;
  std::string name;
  bool isOptional;
  Expression *defVal;
};

class Method
{
  Type type;
  std::string name;
  std::vector<Param> params;
};

class Unit
{
public:
  std::vector<ImportStmt> imports;
  std::vector<BaseDecl> types;
  std::vector<Method> methods;
  std::vector<Statement> stmts;
};

class TypeDecl : public BaseDecl
{
  bool isInterface;
  std::vector<Type> typeArgs;
  std::vector<Field> fields;
  std::vector<Method> method;
};

class EnumDecl : public BaseDecl
{
public:
  std::vector<std::string> cons;
};

class Literal
{
  std::string val;
  bool isBool;
  bool isInt;
  bool isFloat;
};

class NullLit : Expression
{
};

class ExprStmt
{
  Expression expr;
};

class Assign
{
  Expression left;
  Expression right;
  std::string op;
};

class VarDecl
{
  Type type;
  std::string name;
  Expression *right;
};

class Unary
{
  std::string op;
  Expression expr;
};

class Infix
{
  Expression left;
  Expression right;
  std::string op;
};

class Postfix
{
  std::string op;
  Expression expr;
};

class MethodCall
{
  Expression *scope;
  std::string name;
  std::vector<Expression> args;
};

class FieldAccess
{
  Expression scope;
  std::string name;
};

class Block
{
  std::vector<Statement> list;
};

class IfStmt
{
  Expression expr;
  Statement thenStmt;
  Statement *elseStmt;
};

class WhileStmt
{
  Expression expr;
  Statement *body;
};

class DoWhile
{
  Expression expr;
  Block body;
};

class ForStmt
{
  std::vector<VarDecl> decl;
  Expression *cond;
  std::vector<Expression> updaters;
};

class ForEach
{
  VarDecl decl;
  Expression expr;
};

class SwitchStmt
{
  Expression expr;
  std::vector<Case> cases;
};

class Case : Statement
{
  Expression expr;
  Statement body; //can be case
};