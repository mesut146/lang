#pragma once

#include "Ast_all.h"
#include "Visitor.h"
#include <string>
#include <vector>

class Expression {
public:
    virtual std::string print() = 0;
    
    //template <class R, class A>
    virtual void* accept(Visitor<void*, void*>* v, void* arg) = 0;
};
class Statement {
public:
    virtual std::string print() = 0;
    
    //template <class R, class A>
    virtual void* accept(Visitor<void*, void*>* v, void* arg) = 0;
};

class Block : public Statement {
public:
    std::vector<Statement *> list;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class Name : public Expression {
public:
    virtual std::string print() = 0;
    virtual void* accept(Visitor<void*, void*>* v, void* arg) override = 0;
};

class SimpleName : public Name {
public:
    std::string name;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class QName : public Name {
public:
    Name *scope;
    std::string name;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
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
    virtual void* accept(Visitor<void*, void*>* v, void* arg) = 0;
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

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class RefType : public Type {
public:
    Name *name;
    std::vector<Type *> typeArgs;
    
    std::string print();
    void* accept(Visitor<void*, void*>* v, void* arg) override;
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
    std::vector<Type *> typeArgs;
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
    std::string path;

    std::string print();
};

class BaseDecl {
public:
    bool isEnum = false;
    
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

    std::string print() override;
};

class EnumDecl : public BaseDecl {
public:
    std::string *name;
    std::vector<std::string> cons;

    std::string print() override;
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

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ExprStmt : public Statement {
public:
    Expression *expr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
    
    ExprStmt(Expression *e) : expr(e) {}
};

class Fragment {
public:
    std::string name;
    Type *type = nullptr;
    Expression *rhs = nullptr;

    std::string print();
};

class VarDecl : public Statement {
public:
    bool isVar = false;
    std::vector<Fragment> list;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class VarDeclExpr : public Statement {
public:
    bool isVar = false;
    std::vector<Fragment> list;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};


class Unary : public Expression {
public:
    std::string op;
    Expression *expr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class Assign : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class Infix : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class Postfix : public Expression {
public:
    std::string op;
    Expression *expr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class Ternary : public Expression {
public:
    Expression *cond;
    Expression *thenExpr;
    Expression *elseExpr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class MethodCall : public Expression {
public:
    Expression *scope = nullptr;
    std::string name;
    std::vector<Expression *> args;
    bool isOptional = false;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class FieldAccess : public Expression {
public:
    Expression *scope;
    std::string name;
    bool isOptional = false;

    std::string print();
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ArrayAccess : public Expression {
public:
    Expression *array;
    Expression *index;
    bool isOptional = false;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ArrayExpr : public Expression {
public:
    std::vector<Expression *> list;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ParExpr : public Expression {
public:
    Expression *expr;
    
    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ArrowFunction : public Expression {
public:
    std::vector<Param> params;
    Block *block = nullptr;
    Expression *expr = nullptr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
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
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class AnonyObjExpr : public Expression {
public:
    std::vector<Entry> entries;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

/*class XmlElement : public Expression {
public:
    std::string name;
    std::string text;
    std::vector<std::pair<std::string, std::string>> attributes;
    std::vector<XmlElement *> children;
    bool isShort;

    std::string print() override;
};*/

class ReturnStmt : public Statement {
public:
    Expression *expr = nullptr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ContinueStmt : public Statement {
public:
    std::string *label = nullptr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class BreakStmt : public Statement {
public:
    std::string *label = nullptr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class IfStmt : public Statement {
public:
    Expression *expr;
    Statement *thenStmt;
    Statement *elseStmt = nullptr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class WhileStmt : public Statement {
public:
    Expression *expr;
    Statement *body;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class DoWhile : public Statement {
public:
    Expression *expr;
    Block *body;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ForStmt : public Statement {
public:
    VarDeclExpr *decl = nullptr;
    Expression *cond = nullptr;
    std::vector<Expression *> updaters;
    Statement *body;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ForEach : public Statement {
public:
    VarDeclExpr *decl;
    Expression *expr;
    Statement *body;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class ThrowStmt : public Statement {
public:
    Expression *expr;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class CatchStmt : public Statement {
public:
    Block *block;
    Param param;
    
    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};

class TryStmt : public Statement {
public:
    Block *block;
    std::vector<CatchStmt> catches;

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};
