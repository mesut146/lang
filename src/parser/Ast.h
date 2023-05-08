#pragma once

#include <any>
#include <map>
#include <memory>
#include <string>
#include <variant>
#include <vector>

class Visitor;
class Type;
class StructDecl;
class Impl;
class Method;
class Expression;
class Statement;
class VarDecl;
class Block;

template<class T>
using Ptr = std::unique_ptr<T>;

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
        {"bool", 1}};

class Node {
public:
    int pos = 0;
    int line = 0;

    virtual ~Node() = default;
};

class ImportStmt {
public:
    std::vector<std::string> list;

    std::string print();
};
class Unit;
struct Item : public Node {
    Unit *unit;

    virtual bool isClass() { return false; }
    virtual bool isEnum() { return false; }
    virtual bool isTrait() { return false; }
    virtual bool isImpl() { return false; }
    virtual bool isMethod() { return false; }
    virtual bool isExtern() { return false; }
    virtual bool isNs() { return false; }

    virtual std::string print() = 0;
    virtual std::any accept(Visitor *v) = 0;
};

class Unit {
public:
    std::vector<ImportStmt> imports;
    std::vector<std::unique_ptr<Item>> items;
    std::string path;
    int lastLine = 0;

    std::string print();
};

struct BaseDecl : public Item {
    Type *type;
    bool isResolved = false;
    bool isGeneric = false;
    std::unique_ptr<Type> base;
    std::vector<Type *> derives;

    std::string &getName();
};

class FieldDecl : public Node {
public:
    std::string name;
    Type *type;

    FieldDecl(std::string name, Type *type) : name(name), type(type) {}

    std::string print() const;
    std::any accept(Visitor *v);
};

class StructDecl : public BaseDecl {
public:
    std::vector<FieldDecl> fields;

    bool isClass() { return true; }
    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Trait : public Item {
public:
    Type *type;
    std::vector<Method> methods;

    bool isTrait() { return true; }
    std::string print();
    std::any accept(Visitor *v);
};

class Impl : public Item {
public:
    std::vector<Type *> type_params;
    std::unique_ptr<Type> trait_name;
    Type *type;
    std::vector<Method> methods;

    explicit Impl(Type *type) : type(type) {}

    bool isImpl() { return true; }
    std::string print();
    std::any accept(Visitor *v);
};

class EnumVariant {
public:
    std::string name;
    std::vector<FieldDecl> fields;

    bool isStruct() const { return !fields.empty(); }
    std::string print();
};

class EnumDecl : public BaseDecl {
public:
    std::vector<EnumVariant> variants;

    bool isEnum() { return true; }
    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Extern : public Item {
public:
    std::vector<Method> methods;

    bool isExtern() { return true; }
    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Ns : public Item {
public:
    std::vector<Ptr<Item>> items;

    bool isNs() { return true; }
    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Param : public Node {
public:
    std::string name;
    std::unique_ptr<Type> type;

    std::string print();
    std::any accept(Visitor *v);
};

class Method : public Item {
public:
    std::string name;
    std::unique_ptr<Type> type;
    std::vector<Type *> typeArgs;
    std::optional<Param> self;
    std::vector<Param> params;
    std::unique_ptr<Block> body;
    Item *parent = nullptr;
    Unit *unit;
    bool isGeneric = false;
    bool isVirtual = false;

    explicit Method(Unit *unit) : unit(unit) {}

    bool isMethod() override { return true; }
    std::string print();
    std::any accept(Visitor *v);
};

class Expression : public Node {
public:
    //static int last_id = 0;
    int id = -1;
    virtual std::string print() = 0;

    virtual std::any accept(Visitor *v) = 0;
};
class Statement : public Node {
public:
    virtual std::string print() = 0;

    virtual std::any accept(Visitor *v) = 0;
};

class Block : public Statement {
public:
    std::vector<std::unique_ptr<Statement>> list;

    std::string print() override;
    std::any accept(Visitor *v) override;
};


class SimpleName : public Expression {
public:
    std::string name;

    explicit SimpleName(const std::string &name) : name(move(name)){};

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class RefExpr : public Expression {
public:
    std::unique_ptr<Expression> expr;

    RefExpr(std::unique_ptr<Expression> e) : expr(move(e)){};

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class DerefExpr : public Expression {
public:
    std::unique_ptr<Expression> expr;

    DerefExpr(std::unique_ptr<Expression> e) : expr(move(e)){};

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Type : public Expression {
public:
    std::unique_ptr<Type> scope;
    std::string name;
    std::vector<Type *> typeArgs;

    Type() {}
    explicit Type(const std::string &name) : name(move(name)) {}
    explicit Type(Type *scope, const std::string &name) : scope(scope), name(move(name)) {}

    virtual bool isOptional() { return false; }
    virtual bool isArray() { return false; }
    virtual bool isSlice() { return false; }
    virtual bool isPointer() { return false; }

    //Type* unwrap();

    bool isPrim() {
        return sizeMap.find(print()) != sizeMap.end();
    }
    bool isVoid() { return print() == "void"; };
    bool isString() { return print() == "str"; }

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class PointerType : public Type {
public:
    Type *type;
    explicit PointerType(Type *type) : type(type){};

    bool isPointer() override { return true; }
    static Type *unwrap(Type *type) {
        auto ptr = dynamic_cast<PointerType *>(type);
        return ptr ? ptr->type : type;
    }
    std::string print() override;
    //std::any accept(Visitor *v) override;
};
class OptionType : public Type {
public:
    Type *type;

    explicit OptionType(Type *type) : type(type) {}
    bool isOptional() override { return true; }

    std::string print() override;
    //std::any accept(Visitor *v) override;
};

//[type; size]
class ArrayType : public Type {
public:
    Type *type;
    int size;
    ArrayType(Type *type, int size) : type(type), size(size) {}

    bool isArray() override { return true; }
    std::string print() override;
    //std::any accept(Visitor *v) override;
};
//[type]
class SliceType : public Type {
public:
    Type *type;
    SliceType(Type *type) : type(type) {}

    bool isSlice() override { return true; }
    std::string print() override;
};

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
    std::unique_ptr<Type> suffix;

    Literal(LiteralType type, const std::string &val) : type(type), val(move(val)) {}

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class ExprStmt : public Statement {
public:
    Expression *expr;

    std::string print() override;
    std::any accept(Visitor *v) override;

    explicit ExprStmt(Expression *e) : expr(e) {}
};

class Fragment : public Node {
public:
    std::string name;
    std::unique_ptr<Type> type;
    std::unique_ptr<Expression> rhs;
    bool isOptional = false;

    std::string print();
    std::any accept(Visitor *v);
};

class VarDeclExpr : public Statement {
public:
    bool isConst = false;
    bool isStatic = false;
    std::vector<Fragment> list;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class VarDecl : public Statement {
public:
    VarDeclExpr *decl;

    std::string print() override;
    std::any accept(Visitor *v) override;
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
    std::any accept(Visitor *v) override;
};

class Assign : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Infix : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;
    bool isAssign = false;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class AsExpr : public Expression {
public:
    Expression *expr;
    Type *type;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class IsExpr : public Expression {
public:
    Expression *expr;
    Expression *rhs;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Postfix : public Expression {
public:
    std::string op;
    Expression *expr;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Ternary : public Expression {
public:
    Expression *cond;
    Expression *thenExpr;
    Expression *elseExpr;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class MethodCall : public Expression {
public:
    std::unique_ptr<Expression> scope;
    std::string name;
    std::vector<Expression *> args;
    bool isOptional = false;
    std::vector<Type *> typeArgs;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class FieldAccess : public Expression {
public:
    Expression *scope;
    std::string name;
    bool isOptional = false;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class ArrayAccess : public Expression {
public:
    Expression *array;
    Expression *index;
    std::unique_ptr<Expression> index2;
    bool isOptional = false;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class ArrayExpr : public Expression {
public:
    std::vector<Expression *> list;
    std::optional<int> size = std::nullopt;

    bool isSized() { return size.has_value(); }

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class ParExpr : public Expression {
public:
    Expression *expr;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class Entry {
public:
    std::optional<std::string> key;
    Expression *value;
    bool isBase = false;

    //bool hasKey() { return !key.empty(); }

    std::string print();
};

class ObjExpr : public Expression {
public:
    std::unique_ptr<Type> type;
    std::vector<Entry> entries;
    bool isPointer = false;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class ReturnStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class ContinueStmt : public Statement {
public:
    std::optional<std::string> label;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class BreakStmt : public Statement {
public:
    std::optional<std::string> label;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class IfLetStmt : public Statement {
public:
    std::unique_ptr<Type> type;
    std::vector<std::string> args;
    std::unique_ptr<Expression> rhs;
    std::unique_ptr<Statement> thenStmt;
    std::unique_ptr<Statement> elseStmt;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class IfStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Statement> thenStmt;
    std::unique_ptr<Statement> elseStmt;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class WhileStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Statement> body;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class DoWhile : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Block> body;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class ForStmt : public Statement {
public:
    std::unique_ptr<VarDeclExpr> decl;
    std::unique_ptr<Expression> cond;
    std::vector<std::unique_ptr<Expression>> updaters;
    std::unique_ptr<Statement> body;

    std::string print() override;
    std::any accept(Visitor *v) override;
};

class AssertStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;

    explicit AssertStmt(Expression *expr) : expr(std::unique_ptr<Expression>(expr)) {}

    std::string print() override;
    std::any accept(Visitor *v) override;
};
