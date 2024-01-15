#pragma once

#include <any>
#include <map>
#include <memory>
#include <optional>
#include <string>
#include <variant>
#include <vector>


class Visitor;
class Type;
class StructDecl;
class Impl;
//class Method;
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
        {"bool", 8}};

class Node {
public:
    int pos = 0;
    int line = 0;
    int id = -1;
    static int last_id;

    virtual ~Node() = default;

    template<class T>
    static T *make() {
        auto res = new T();
        res->id = last_id++;
        return res;
    }
};
class Expression : public Node {
public:
    virtual std::string print() const = 0;

    virtual std::any accept(Visitor *v) = 0;
};
class Type : public Expression {
public:
    std::unique_ptr<Type> scope;
    std::string name;
    std::vector<Type> typeArgs;
    int size;
    enum Kind {
        Prim,
        Simple,
        Pointer,
        Option,
        Array,
        Slice,
        None
    };
    Kind kind = None;

    Type() = default;
    Type(const Type &rhs) {
        (*this) = rhs;
    }
    Type &operator=(const Type &rhs) {
        kind = rhs.kind;
        if (rhs.scope) {
            set(*rhs.scope.get());
        } else {
            scope.reset();
        }
        name = rhs.name;
        typeArgs = rhs.typeArgs;
        size = rhs.size;
        return *this;
    }

    explicit Type(const std::string &name) : name(name) {}
    explicit Type(const Type &scope, const std::string &name) : name(name) {
        set(scope);
    }
    Type(Kind kind, const Type &inner) : kind(kind) {
        set(inner);
    }
    Type(const Type &inner, int size) : kind(Array), size(size) {
        set(inner);
    }

    void set(const Type &type) {
        scope = std::make_unique<Type>(type);
    }
    bool isArray() const { return kind == Array; }
    bool isSlice() const { return kind == Slice; }
    bool isPointer() const { return kind == Pointer; }

    Type unwrap() const {
        if (isPointer()) return *scope.get();
        return *this;
    }

    bool isPrim() const {
        return sizeMap.find(print()) != sizeMap.end();
    }
    bool isVoid() const { return print() == "void"; };
    bool isString() const { return print() == "str"; }

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class ImportStmt {
public:
    std::vector<std::string> list;

    std::string print() const;
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
    virtual bool isType() { return false; }

    virtual std::string print() const = 0;
    virtual std::any accept(Visitor *v) = 0;
};

struct TypeItem : public Item {
    std::string name;
    Type rhs;

    explicit TypeItem(const std::string &name, const Type &rhs) : name(name), rhs(rhs) {}
    std::string print() const;
    std::any accept(Visitor *v);
    bool isType() { return true; }
};

struct Global{
    std::string name;
    std::optional<Type> type;
    std::unique_ptr<Expression> expr;
};

class Unit {
public:
    std::vector<ImportStmt> imports;
    std::vector<Global> globals;
    std::vector<std::unique_ptr<Item>> items;
    std::string path;
    int lastLine = 0;

    std::string print();
};

struct BaseDecl : public Item {
    Type type;
    bool isResolved = false;
    bool isGeneric = false;
    std::optional<Type> base;
    std::vector<Type> derives;

    //explicit BaseDecl(const Type &type) : type(type) {}
    std::string &getName();
};

class FieldDecl : public Node {
public:
    std::string name;
    Type type;

    FieldDecl(const std::string &name, const Type &type) : name(name), type(type) {}

    std::string print() const;
    std::any accept(Visitor *v);
};

class StructDecl : public BaseDecl {
public:
    std::vector<FieldDecl> fields;

    bool isClass() override { return true; }
    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class Param : public Node {
public:
    std::string name;
    std::optional<Type> type;

    explicit Param(const std::string &name) : name(name) {}
    explicit Param(const std::string &name, const Type &type) : name(name), type(type){};
    std::string print() const;
    std::any accept(Visitor *v);
};

class Method : public Item {
public:
    std::string name;
    Type type;
    std::vector<Type> typeArgs;
    std::optional<Param> self;
    std::vector<Param> params;
    std::unique_ptr<Block> body;
    Item *parent = nullptr;
    Unit *unit;
    bool isGeneric = false;
    bool isVirtual = false;

    explicit Method(Unit *unit) : unit(unit) {}

    bool isMethod() override { return true; }
    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class Trait : public Item {
public:
    Type type;
    std::vector<Method> methods;

    explicit Trait(const Type &type) : type(type) {}
    bool isTrait() override { return true; }
    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class Impl : public Item {
public:
    std::vector<Type> type_params;
    std::optional<Type> trait_name;
    Type type;
    std::vector<Method> methods;

    explicit Impl(const Type &type) : type(type) {}

    bool isImpl() override { return true; }
    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class EnumVariant : public Node {
public:
    std::string name;
    std::vector<FieldDecl> fields;

    bool isStruct() const { return !fields.empty(); }
    std::string print() const;
};

class EnumDecl : public BaseDecl {
public:
    std::vector<EnumVariant> variants;

    bool isEnum() override { return true; }
    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class Extern : public Item {
public:
    std::vector<Method> methods;

    bool isExtern() override { return true; }
    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class Ns : public Item {
public:
    std::vector<Ptr<Item>> items;

    bool isNs() override { return true; }
    std::string print() const override;
    std::any accept(Visitor *v) override;
};


class Statement : public Node {
public:
    virtual std::string print() const = 0;

    virtual std::any accept(Visitor *v) = 0;
};

class Block : public Statement {
public:
    std::vector<std::unique_ptr<Statement>> list;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class MatchArm {
public:
    std::optional<Type> type;
    std::vector<std::string> args;
    Ptr<Statement> rhs;

    bool us() const { return !type.has_value(); }
};

class Match : public Statement {
public:
    Ptr<Expression> expr;
    std::vector<MatchArm> arms;

    std::string print() const override { return "match"; };
    std::any accept(Visitor *v) override { return {}; };
};

class SimpleName : public Expression {
public:
    std::string name;

    explicit SimpleName(const std::string &name) : name(name){};

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class RefExpr : public Expression {
public:
    std::unique_ptr<Expression> expr;

    RefExpr(std::unique_ptr<Expression> e) : expr(std::move(e)){};

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class DerefExpr : public Expression {
public:
    std::unique_ptr<Expression> expr;

    DerefExpr(std::unique_ptr<Expression> e) : expr(std::move(e)){};

    std::string print() const override;
    std::any accept(Visitor *v) override;
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
    LiteralType type;
    std::string val;
    std::optional<Type> suffix;

    Literal(LiteralType type, const std::string &val) : type(type), val(val) {}

    std::string print() const override;
    std::any accept(Visitor *v) override;
};


class Unary : public Expression {
public:
    /*enum ops {
        PLUS,
        MINUS,
        PLUSPLUS,
        MINUSMINUS,
        BANG,
        TILDE,
    };*/
    std::string op;
    Expression *expr;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class Assign : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class Infix : public Expression {
public:
    Expression *left;
    Expression *right;
    std::string op;
    bool isAssign = false;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class AsExpr : public Expression {
public:
    Expression *expr;
    Type type;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class IsExpr : public Expression {
public:
    Expression *expr;
    Expression *rhs;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};


class MethodCall : public Expression {
public:
    std::unique_ptr<Expression> scope;
    std::string name;
    std::vector<Expression *> args;
    bool is_static = false;
    std::vector<Type> typeArgs;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class FieldAccess : public Expression {
public:
    Expression *scope;
    std::string name;
    bool isOptional = false;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class ArrayAccess : public Expression {
public:
    Expression *array;
    Expression *index;
    std::unique_ptr<Expression> index2;
    bool isOptional = false;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class ArrayExpr : public Expression {
public:
    std::vector<Expression *> list;
    std::optional<int> size = std::nullopt;

    bool isSized() const { return size.has_value(); }

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class ParExpr : public Expression {
public:
    Expression *expr;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class Entry {
public:
    std::optional<std::string> key;
    Expression *value;
    bool isBase = false;

    //bool hasKey() { return !key.empty(); }

    std::string print() const;
};

class ObjExpr : public Expression {
public:
    Type type;
    std::vector<Entry> entries;
    bool isPointer = false;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

//STATEMENTS----------------------------------------------
class ExprStmt : public Statement {
public:
    Expression *expr;

    std::string print() const override;
    std::any accept(Visitor *v) override;

    explicit ExprStmt(Expression *e) : expr(e) {}
};

class Fragment : public Node {
public:
    std::string name;
    std::optional<Type> type;
    std::unique_ptr<Expression> rhs;
    bool isOptional = false;

    std::string print() const;
    std::any accept(Visitor *v);
};

class VarDeclExpr : public Statement {
public:
    bool isConst = false;
    bool isStatic = false;
    std::vector<Fragment> list;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class VarDecl : public Statement {
public:
    VarDeclExpr *decl;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class ReturnStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class ContinueStmt : public Statement {
public:
    std::optional<std::string> label;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class BreakStmt : public Statement {
public:
    std::optional<std::string> label;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

struct ArgBind {
    std::string name;
    bool ptr = false;

    explicit ArgBind(const std::string &name) : name(name) {}

    std::string print() const{
        if(ptr){
            return name + "*";
        }
        return name;
    }
};

class IfLetStmt : public Statement {
public:
    Type type;
    std::vector<ArgBind> args;
    std::unique_ptr<Expression> rhs;
    std::unique_ptr<Statement> thenStmt;
    std::unique_ptr<Statement> elseStmt;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class IfStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Statement> thenStmt;
    std::unique_ptr<Statement> elseStmt;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class WhileStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Statement> body;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class DoWhile : public Statement {
public:
    std::unique_ptr<Expression> expr;
    std::unique_ptr<Block> body;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class ForStmt : public Statement {
public:
    std::unique_ptr<VarDeclExpr> decl;
    std::unique_ptr<Expression> cond;
    std::vector<std::unique_ptr<Expression>> updaters;
    std::unique_ptr<Statement> body;

    std::string print() const override;
    std::any accept(Visitor *v) override;
};

class AssertStmt : public Statement {
public:
    std::unique_ptr<Expression> expr;

    explicit AssertStmt(Expression *expr) : expr(std::unique_ptr<Expression>(expr)) {}

    std::string print() const override;
    std::any accept(Visitor *v) override;
};
