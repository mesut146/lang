#pragma once

#include "parser/Ast.h"
#include <llvm/IR/Value.h>
#include <optional>

struct Resolver;
struct Compiler;
struct RType;

struct Variable {
    std::string name;
    llvm::Value *ptr;
    int id;
    int line;
    int moveLine = -1;

    Variable(const std::string &name, llvm::Value *ptr, int id, int line) : name(name), ptr(ptr), id(id), line(line) {}
};

//dropable
struct Object {
    Expression *expr;
    llvm::Value *ptr;
    int id;          //prm
    std::string name;//prm

    static Object make(Expression *expr) {
        return Object{expr, nullptr, expr->id, ""};
    }
};

struct Move {
    Variable *lhs = nullptr;//null means transfer
    Object rhs;
    int line;

    static Move make_var_move(Variable *lhs, const Object &rhs) {
        Move m;
        m.lhs = lhs;
        m.rhs = rhs;
        m.line = rhs.expr->line;
        return m;
    }

    static Move make_transfer(const Object& rhs) {
        Move res;
        res.rhs = rhs;
        res.line = rhs.expr->line;
        return res;
    }
};

struct VarScope {
    std::vector<Variable> vars;
    std::vector<Move> moves;
    std::vector<Object> objects;
    VarScope *next_scope = nullptr;
    VarScope *parent = nullptr;
};

struct Ownership {
    Compiler *compiler;
    Resolver *r;
    Method *method;
    VarScope scope;
    VarScope *last_scope = nullptr;

    Ownership(Compiler *compiler, Method *m);


    VarScope *newScope() {
        auto then = new VarScope;
        then->parent = last_scope;
        last_scope->next_scope = then;
        last_scope = then;
        return then;
    }

    void restore(VarScope *then) {
        last_scope->next_scope = then;
    }

    void dropScope(VarScope *then) {
    }

    //drop vars in this scope
    void endScope(VarScope *s);

    bool isDropType(const RType &rt);
    bool isDropType(const Type &type);
    bool isDrop(BaseDecl *decl);

    Variable *find(std::string &name, int id);

    void addPtr(Expression *expr, llvm::Value *ptr) {
        last_scope->objects.push_back({expr, ptr, expr->id, std::string("")});
    }

    /*void bindPtr(Fragment &f, llvm::Value *ptr) {
        for (int i = 0; i < last_scope->objects.size(); ++i) {
            auto &ob = objects[i];
            if (ob.ptr == ptr) {
                return;
            }
        }
    }*/

    void check(Expression *expr);

    void add(std::string &name, Type &type, llvm::Value *ptr, int id, int line);

    void add(Fragment &f, Type &type, llvm::Value *ptr) {
        add(f.name, type, ptr, f.id, f.line);
    }

    void addPrm(Param &p, llvm::Value *ptr) {
        add(p.name, p.type.value(), ptr, p.id, p.line);
        last_scope->objects.push_back({nullptr, ptr, p.id, p.name});
    }

    void doMove(Expression *expr);

    void doAssign(Expression *lhs, Expression *rhs);
    void endAssign(Expression *lhs);

    //send(expr) //moves expr
    void doMoveCall(Expression *expr);

    void doMoveReturn(Expression *expr);

    void moveToField(Expression *expr);


    Variable *isMoved(SimpleName *sn);

    bool needDrop() { return false; }

    void doReturn();

    void drop(Expression *expr, llvm::Value *ptr);
};