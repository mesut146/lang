#pragma once

#include <map>
#include <memory>
#include <string>
#include <vector>

class Visitor;
class Type;
class BaseDecl;
class TypeDecl;
class Method;
class Expression;
class Statement;
class Name;
class VarDecl;
class Block;

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


class ImportStmt {
public:
    std::vector<std::string> list;

    std::string print();
};

class Unit {
public:
    std::vector<ImportStmt *> imports;
    std::vector<std::unique_ptr<BaseDecl>> types;
    std::vector<std::unique_ptr<Method>> methods;
    std::vector<std::unique_ptr<Statement>> stmts;
    std::string path;

    std::string print();
};

class BaseDecl {
public:
    std::string name;
    std::vector<Type *> typeArgs;
    bool isEnum = false;
    bool isResolved = false;
    std::vector<std::unique_ptr<Method>> methods;

    virtual bool isTrait() { return false; }
    virtual bool isImpl() { return false; }
    virtual std::string print() = 0;
    virtual void *accept(Visitor *v);
};
class FieldDecl {
public:
    std::string name;
    Type *type;
    TypeDecl *parent;
    FieldDecl(std::string name, Type *type, TypeDecl *parent) : name(name), type(type), parent(parent) {}

    std::string print() const;

    virtual void *accept(Visitor *v);
};
class TypeDecl : public BaseDecl {
public:
    std::vector<std::unique_ptr<FieldDecl>> fields;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class Trait : public BaseDecl {
public:
    virtual bool isTrait() { return true; }
    std::string print() override;
    void *accept(Visitor *v) override;
};

class Impl : public BaseDecl {
public:
    std::optional<std::string> trait_name;
    std::unique_ptr<Type> type;

    virtual bool isImpl() { return true; }
    std::string print() override;
    void *accept(Visitor *v) override;
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
    void *accept(Visitor *v) override;
};

class Param {
public:
    std::string name;
    std::unique_ptr<Type> type;
    Method *method;

    std::string print();
    void *accept(Visitor *v);
};

class Method {
public:
    bool isStatic = false;
    std::string name;
    std::unique_ptr<Type> type;
    std::vector<Type *> typeArgs;
    std::optional<std::string> self;
    std::vector<Param *> params;
    std::unique_ptr<Block> body;
    BaseDecl *parent = nullptr;
    Unit *unit;

    explicit Method(Unit *unit) : unit(unit) {}

    std::string print();
    void *accept(Visitor *v);
};

class Expression {
public:
    virtual std::string print() = 0;

    virtual void *accept(Visitor *v) = 0;
};
class Statement {
public:
    virtual std::string print() = 0;

    virtual void *accept(Visitor *v) = 0;
};

class Block : public Statement {
public:
    std::vector<std::unique_ptr<Statement>> list;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class UnsafeBlock : public Expression {
public:
    Block *body;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class UnwrapExpr : public Expression {
public:
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class Name : public Expression {
public:
    std::vector<Type *> typeArgs;

    virtual bool isSimple() { return false; };
    std::string print() override = 0;
    void *accept(Visitor *v) override = 0;
};

class SimpleName : public Name {
public:
    std::string name;

    explicit SimpleName(std::string name) : name(name){};

    bool isSimple() override { return true; };
    std::string print() override;
    void *accept(Visitor *v) override;
};

class QName : public Name {
public:
    Name *scope;
    std::string name;

    QName(Name *scope, std::string name) : scope(scope), name(name){};

    std::string print() override;
    void *accept(Visitor *v) override;
};

class RefExpr : public Expression {
public:
    Expression *expr;

    RefExpr(Expression *expr) : expr(expr){};

    std::string print() override;
    void *accept(Visitor *v) override;
};

class DerefExpr : public Expression {
public:
    Expression *expr;

    DerefExpr(Expression *expr) : expr(expr){};

    std::string print() override;
    void *accept(Visitor *v) override;
};

class Type : public Expression {
public:
    Type *scope = nullptr;
    std::string name;
    std::vector<Type *> typeArgs;
    bool isTypeArg = false;

    Type() {}
    explicit Type(std::string name) : name(name) {}
    explicit Type(Type *scope, std::string name) : scope(scope), name(name) {}

    virtual bool isOptional() { return false; }
    virtual bool isArray() { return false; }
    virtual bool isPointer() { return false; }

    bool isPrim() {
        return isIntegral() || print() == "bool";
    }
    bool isIntegral() {
        auto str = print();
        auto it = sizeMap.find(str);
        return it != sizeMap.end();
    }
    bool isVoid() { return print() == "void"; };
    bool isString() { return print() == "core/string"; }

    std::string print() override;
    void *accept(Visitor *v) override;
};

class PointerType : public Type {
public:
    Type *type;
    explicit PointerType(Type *type) : type(type){};

    bool isPointer() override { return true; }
    std::string print() override;
    //void *accept(Visitor *v) override;
};
class OptionType : public Type {
public:
    Type *type;

    explicit OptionType(Type *type) : type(type) {}
    bool isOptional() override { return true; }

    std::string print() override;
    //void *accept(Visitor *v) override;
};

class ArrayType : public Type {
public:
    Type *type;
    std::vector<Expression *> dims;

    bool isArray() override { return true; }
    std::string print() override;
    //void *accept(Visitor *v) override;
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
    void *accept(Visitor *v) override;
};

class ExprStmt : public Statement {
public:
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v) override;

    explicit ExprStmt(Expression *e) : expr(e) {}
};

class Fragment {
public:
    std::string name;
    std::unique_ptr<Type> type;
    std::unique_ptr<Expression> rhs;
    bool isOptional = false;

    std::string print();
    void *accept(Visitor *v);
};

class VarDeclExpr : public Statement {
public:
    bool isConst = false;
    bool isStatic = false;
    std::vector<Fragment *> list;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class VarDecl : public Statement {
public:
    VarDeclExpr *decl;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class Unary : public Expression {
public:
    enum ops {
        PLUS,
        MINUS,
        PLUSPLUS,
        MINUSMINUS,
        BANG,
        TILDE,
    };
    std::string op;
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class Assign : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class Infix : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;
    bool isAssign = false;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class AsExpr : public Expression {
public:
    Expression *expr;
    Type *type;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class IsExpr : public Expression {
public:
    Expression *expr;
    Type *type;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class Postfix : public Expression {
public:
    std::string op;
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class Ternary : public Expression {
public:
    Expression *cond;
    Expression *thenExpr;
    Expression *elseExpr;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class MethodCall : public Expression {
public:
    std::unique_ptr<Expression> scope;
    std::string name;
    std::vector<Expression *> args;
    bool isOptional = false;
    std::vector<Type *> typeArgs;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class FieldAccess : public Expression {
public:
    Expression *scope;
    std::string name;
    bool isOptional = false;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class ArrayAccess : public Expression {
public:
    Expression *array;
    Expression *index;
    bool isOptional = false;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class ArrayExpr : public Expression {
public:
    std::vector<Expression *> list;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class ArrayCreation : public Expression {
public:
    Type *type;
    std::vector<Expression *> dims;
    bool isPointer = false;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class ParExpr : public Expression {
public:
    Expression *expr;

    std::string print() override;
    void *accept(Visitor *v) override;
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
    std::unique_ptr<Type> type;
    std::vector<Entry> entries;
    bool isPointer = false;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class ReturnStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class ContinueStmt : public Statement {
public:
    std::optional<std::string> label;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class BreakStmt : public Statement {
public:
    std::optional<std::string> label;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class IfLetStmt : public Statement {
public:
    std::unique_ptr<Type> type;
    std::vector<std::string> args;
    std::unique_ptr<Expression> rhs;
    std::unique_ptr<Statement> thenStmt;
    std::unique_ptr<Statement> elseStmt;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class IfStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Statement> thenStmt;
    std::unique_ptr<Statement> elseStmt;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class WhileStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Statement> body;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class DoWhile : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Block> body;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class ForStmt : public Statement {
public:
    VarDeclExpr *decl = nullptr;
    std::unique_ptr<Expression> cond;
    std::vector<std::unique_ptr<Expression>> updaters;
    std::unique_ptr<Statement> body;

    std::string print() override;
    void *accept(Visitor *v) override;
};

class AssertStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;

    explicit AssertStmt(Expression *expr) : expr(std::unique_ptr<Expression>(expr)) {}

    std::string print() override;
    void *accept(Visitor *v) override;
};
