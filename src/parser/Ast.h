#pragma once

#include "Ast_all.h"
//#include "Visitor.h"
#include <map>
#include <string>
#include <vector>

class Visitor;

static std::map<std::string, int> sizeMap{
        {"i8", 8},
        {"i16", 16},
        {"i32", 32},
        {"i64", 64},
        {"u8", 8},
        {"u16", 16},
        {"u32", 32},
        {"u64", 64},
        {"f32", 32},
        {"f64", 64},
        {"bool", 1},
        {"byte", 8},
        {"char", 16},
        {"short", 16},
        {"int", 32},
        {"long", 64},
        {"float", 32},
        {"double", 64}};

class FieldDecl {
public:
    std::string name;
    Type *type;
    TypeDecl* parent;

    std::string print() const;

    virtual void *accept(Visitor *v, void *arg);
};

class Unit {
public:
    std::vector<ImportStmt *> imports;
    std::vector<BaseDecl *> types;
    std::vector<Method *> methods;
    std::vector<Statement *> stmts;
    std::string path;

    std::string print();
};

class ImportAlias {
public:
    std::string name;
    std::string *as = nullptr;

    std::string print();
};

class NormalImport {
public:
    Name *path;
    std::string *as = nullptr;
};

class SymbolImport {
public:
    Name *path;
    std::vector<ImportAlias> entries;
};

class ImportStmt {
public:
    NormalImport *normal = nullptr;
    SymbolImport *sym = nullptr;

    std::string print();
};

class BaseDecl {
public:
    std::string name;
    std::vector<Type *> typeArgs;
    bool isEnum = false;
    bool isResolved = false;
    std::vector<Method *> methods;

    virtual std::string print() = 0;
    virtual void *accept(Visitor *v, void *arg);
};

class TypeDecl : public BaseDecl {
public:
    bool isInterface;
    std::vector<FieldDecl *> fields;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class EnumParam {
public:
    std::string name;
    Type *type;

    std::string print();
};

class EnumVariant {
public:
    std::string name;
    std::vector<EnumParam *> fields;

    bool isStruct() const { return !fields.empty(); }
    std::string print();
};

class EnumDecl : public BaseDecl {
public:
    std::vector<EnumVariant *> variants;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Method {
public:
    bool isStatic = false;
    Type *type = nullptr;
    std::string name;
    std::vector<Type *> typeArgs;
    std::vector<Param *> params;
    Block *body = nullptr;
    BaseDecl *parent = nullptr;

    std::string print();
    void *accept(Visitor *v, void *arg);
};

class Param {
public:
    std::string name;
    Type *type = nullptr;
    Expression *defVal = nullptr;
    Method *method = nullptr;

    std::string print();
    void *accept(Visitor *v, void *arg);
};

class Expression {
public:
    virtual std::string print() = 0;

    virtual void *accept(Visitor *v, void *arg) = 0;
};
class Statement {
public:
    virtual std::string print() = 0;

    virtual void *accept(Visitor *v, void *arg) = 0;
};

class Block : public Statement {
public:
    std::vector<Statement *> list;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class UnsafeBlock : public Expression {
public:
    Block *body;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class UnwrapExpr : public Expression {
public:
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Name : public Expression {
public:
    std::vector<Type *> typeArgs;

    virtual bool isSimple() { return false; };
    std::string print() override = 0;
    void *accept(Visitor *v, void *arg) override = 0;
};

class SimpleName : public Name {
public:
    std::string name;
    void *parent = nullptr;

    explicit SimpleName(std::string name) : name(name){};

    bool isSimple() override { return true; };
    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class QName : public Name {
public:
    Name *scope;
    std::string name;

    QName(Name *scope, std::string name) : scope(scope), name(name){};

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class RefExpr : public Expression {
public:
    Expression *expr;

    RefExpr(Expression *expr) : expr(expr){};

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class DerefExpr : public Expression {
public:
    Expression *expr;

    DerefExpr(Expression *expr) : expr(expr){};

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Type : public Expression {
public:
    Type *scope = nullptr;
    std::string name;
    std::vector<Type *> typeArgs;
    std::vector<Expression *> dims;
    bool isTypeArg = false;

    virtual bool isOptional() { return false; }

    bool isPrim() {
        auto str = print();
        return isIntegral() || str == "bool";
    }
    bool isIntegral() {
        auto str = print();
        auto it = sizeMap.find(str);
        return it != sizeMap.end();
    }
    bool isVoid() { return print() == "void"; };
    bool isString() { return print() == "core/string"; }
    bool isArray() const { return !dims.empty(); }

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class PointerType : public Type {
public:
    Type *type;
    explicit PointerType(Type *type) : type(type){};

    std::string print() override;
    //void *accept(Visitor *v, void *arg) override;
};
class OptionType : public Type {
public:
    Type *type;
    
    explicit OptionType(Type *type) : type(type) {}
    bool isOptional() override { return true; }

    std::string print() override;
    //void *accept(Visitor *v, void *arg) override;
};

class ArrayType : public Type {
public:
    Type *type;
    std::vector<Expression *> dims;

    std::string print() override;
    //void *accept(Visitor *v, void *arg) override;
};

/*class SimpleType : public Type {
public:
    std::string type;
    bool isTypeVar_;
    
    bool isTypeVar() { return isTypeVar_; }
    
    bool isPrim() {
        return type == "int" || type == "long" || type == "char" || type == "byte" ||
               type == "short" || type == "float" || type == "double" || type == "bool";
    }
    bool isVoid() {
        return type == "void";
    }

    std::string print() override;
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};*/

/*class RefType : public Type {
public:
    Name *name;
    std::vector<Type *> typeArgs;
    
    bool isString(){
      return name->print() == "core.string";
    }
    
    std::string print();
    void* accept(Visitor<void*, void*>* v, void* arg) override;
};*/

class Literal : public Expression {
public:
    enum LiteralType {
        BOOL,
        INT,
        FLOAT,
        STR,
        CHAR,
    };
    std::string val;
    LiteralType type;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ExprStmt : public Statement {
public:
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;

    explicit ExprStmt(Expression *e) : expr(e) {}
};

class Fragment {
public:
    std::string name;
    Type *type = nullptr;
    Expression *rhs = nullptr;
    bool isOptional = false;
    VarDecl *vd = nullptr;

    std::string print();
    void *accept(Visitor *v, void *arg);
};

class VarDecl : public Statement {
public:
    VarDeclExpr *decl;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class VarDeclExpr : public Statement {
public:
    bool isConst = false;
    bool isStatic = false;
    std::vector<Fragment *> list;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Unary : public Expression {
public:
    std::string op;
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Assign : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Infix : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class AsExpr : public Expression {
public:
    Expression *expr;
    Type *type;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class IsExpr : public Expression {
public:
    Expression *expr;
    Type *type;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Postfix : public Expression {
public:
    std::string op;
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Ternary : public Expression {
public:
    Expression *cond;
    Expression *thenExpr;
    Expression *elseExpr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class MethodCall : public Expression {
public:
    Expression *scope = nullptr;
    std::string name;
    std::vector<Expression *> args;
    bool isOptional = false;
    std::vector<Type *> typeArgs;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class FieldAccess : public Expression {
public:
    Expression *scope;
    std::string name;
    bool isOptional = false;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ArrayAccess : public Expression {
public:
    Expression *array;
    Expression *index;
    bool isOptional = false;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ArrayExpr : public Expression {
public:
    std::vector<Expression *> list;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ArrayCreation : public Expression {
public:
    Type *type;
    std::vector<Expression *> dims;
    bool isPointer = false;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ParExpr : public Expression {
public:
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class Entry {
public:
    std::string key;
    Expression *value;

    bool hasKey() { return !key.empty(); }

    std::string print();
};

class ObjExpr : public Expression {
public:
    Type *type;
    std::vector<Entry> entries;
    bool isPointer = false;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class MapEntry {
public:
    Expression *key;
    Expression *value;

    std::string print();
};

class MapExpr : public Expression {
public:
    std::vector<MapEntry> entries;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ReturnStmt : public Statement {
public:
    Expression *expr = nullptr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ContinueStmt : public Statement {
public:
    std::string *label = nullptr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class BreakStmt : public Statement {
public:
    std::string *label = nullptr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class IfLetStmt : public Statement {
public:
    Type *type;
    std::vector<std::string> args;
    Expression *rhs;
    Statement *thenStmt;
    Statement *elseStmt = nullptr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class IfStmt : public Statement {
public:
    Expression *expr;
    Statement *thenStmt;
    Statement *elseStmt = nullptr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class WhileStmt : public Statement {
public:
    Expression *expr;
    Statement *body;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class DoWhile : public Statement {
public:
    Expression *expr;
    Block *body;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ForStmt : public Statement {
public:
    VarDeclExpr *decl = nullptr;
    Expression *cond = nullptr;
    std::vector<Expression *> updaters;
    Statement *body;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class ForEach : public Statement {
public:
    VarDeclExpr *decl;
    Expression *expr;
    Statement *body;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};

class AssertStmt : public Statement {
public:
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v, void *arg) override;
};
