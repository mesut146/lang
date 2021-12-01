#pragma once

#include "Ast_all.h"
#include <string>
#include <vector>

class Expression {
public:
    virtual std::string print() = 0;
};
class Statement {
public:
    virtual std::string print() = 0;
};

class Block : public Statement {
public:
    std::vector<Statement *> list;

    std::string print();
};

class Name : public Expression {
public:
    virtual std::string print() = 0;
};

class SimpleName : public Name {
public:
    std::string name;

    std::string print();
};

class QName : public Name {
public:
    Name *scope;
    std::string name;

    std::string print();
};
class NamedImport {
public:
    std::string name;
    std::string *as = nullptr;

    std::string print();
};

class ImportStmt {
public:
    std::vector<NamedImport> namedImports;
    std::string from;
    bool isStar;
    std::string *as = nullptr;

    std::string print();
};

class Type : public Expression {
public:
    int arrayLevel = 0;

    virtual bool isVar() { return false; };
    //virtual bool isTypeVar() = 0;
    virtual bool isPrim() { return false; };
    virtual bool isVoid() { return false; };

    virtual std::string print() = 0;
};

class SimpleType : public Type {
public:
    std::string *type;
    bool isVar() {
        return *type == "var";
    }
    bool isTypeVar;
    bool isPrim() {
        return *type == "int" || *type == "long" || *type == "char" || *type == "byte" ||
               *type == "short" || *type == "float" || *type == "double";
    }
    bool isVoid() {
        return *type == "void";
    }

    std::string print();
};

class RefType : public Type {
public:
    Name *name;
    std::vector<Type *> typeArgs;
    std::string print();
};

class Param {
public:
    Type *type;
    std::string name;
    bool isOptional = false;
    Expression *defVal = nullptr;

    std::string print();
};

class Method {
public:
    Type *type;
    std::string name;
    std::vector<Param> params;
    Block *body = nullptr;

    std::string print();
};

class Unit {
public:
    std::vector<ImportStmt> imports;
    std::vector<BaseDecl *> types;
    std::vector<Method *> methods;
    std::vector<Statement *> stmts;

    std::string print();
};

class BaseDecl {
public:
    virtual std::string print() = 0;
};

class TypeDecl : public BaseDecl {
public:
    std::string name;
    bool isInterface;
    std::vector<Type *> typeArgs;
    std::vector<Type *> baseTypes;
    std::vector<FieldDecl *> fields;
    std::vector<Method *> methods;
    std::vector<BaseDecl *> types;

    std::string print();
};

class EnumDecl : public BaseDecl {
public:
    std::string *name;
    std::vector<std::string> cons;

    std::string print();
};

class FieldDecl {
public:
    std::string name;
    bool isOptional;
    Type *type;
    Expression *expr;

    std::string print();
};

class Literal : public Expression {
public:
    std::string val;
    bool isBool;
    bool isInt;
    bool isFloat;
    bool isStr;
    bool isChar;

    std::string print();
};

class ExprStmt : public Statement {
public:
    Expression *expr;
    std::string print() override;
    ExprStmt(Expression *e) : expr(e) {}
};

class Fragment {
public:
    std::string name;
    Type *type;
    Expression *rhs = nullptr;

    std::string print();
};

class VarDecl : public Statement {
public:
    bool isVar = false;
    std::vector<Fragment> list;

    std::string print() override;
};
class VarDeclExpr : public Statement {
public:
    bool isVar = false;
    std::vector<Fragment> list;

    std::string print() override;
};


class Unary : public Expression {
public:
    std::string op;
    Expression *expr;

    std::string print() override;
};

class Assign : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() override;
};

class Infix : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() override;
};

class Postfix : public Expression {
public:
    std::string op;
    Expression *expr;

    std::string print() override;
};

class Ternary : public Expression {
public:
    Expression *cond;
    Expression *thenExpr;
    Expression *elseExpr;

    std::string print() override;
};

class MethodCall : public Expression {
public:
    Expression *scope;
    std::string name;
    std::vector<Expression *> args;
    bool isOptional = false;

    std::string print() override;
};

class FieldAccess : public Expression {
public:
    Expression *scope;
    std::string name;
    bool isOptional = false;

    std::string print();
};

class ArrayAccess : public Expression {
public:
    Expression *array;
    Expression *index;
    bool isOptional = false;

    std::string print();
};

class ArrayExpr : public Expression {
public:
    std::vector<Expression *> list;

    std::string print();
};

class ParExpr : public Expression {
public:
    Expression *expr;
    std::string print() override;
};

class ArrowFunction : public Expression {
public:
    std::vector<Param> params;
    Block *block = nullptr;
    Expression *expr = nullptr;

    std::string print() override;
};

class Entry {
public:
    Expression *key;
    Expression *value;

    std::string print();
};

class ObjExpr : public Expression {
public:
    std::string name;
    std::vector<Entry> entries;
    std::string print() override;
};

class AnonyObjExpr : public Expression {
public:
    std::vector<Entry> entries;
    std::string print() override;
};

class ReturnStmt : public Statement {
public:
    Expression *expr;
    std::string print() override;
};

class ContinueStmt : public Statement {
public:
    std::string *label;
    std::string print() override;
};

class BreakStmt : public Statement {
public:
    std::string *label;

    std::string print() override;
};

class IfStmt : public Statement {
public:
    Expression *expr;
    Statement *thenStmt;
    Statement *elseStmt;

    std::string print() override;
};

class WhileStmt : public Statement {
public:
    Expression *expr;
    Statement *body;

    std::string print() override;
};

class DoWhile : public Statement {
public:
    Expression *expr;
    Block *body;

    std::string print() override;
};

class ForStmt : public Statement {
public:
    VarDeclExpr *decl;
    Expression *cond;
    std::vector<Expression *> updaters;
    Statement *body;

    std::string print() override;
};

class ForEach : public Statement {
public:
    VarDeclExpr *decl;
    Expression *expr;
    Statement *body;

    std::string print() override;
};

class ThrowStmt : public Statement {
public:
    Expression *expr;

    std::string print() override;
};

class CatchStmt : public Statement {
public:
    Block *block;
    Param param;
    std::string print() override;
};

class TryStmt : public Statement {
public:
    Block *block;
    std::vector<CatchStmt> catches;

    std::string print() override;
};
