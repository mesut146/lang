#pragma once

#include "parser/Ast.h"
#include <llvm/IR/Value.h>

struct Resolver;
struct RType;

struct Variable {
    std::string name;
    llvm::Value *ptr;
    int id;
    int line;
    int moveLine = -1;

    Variable(const std::string &name, llvm::Value *ptr, int id, int line) : name(name), ptr(ptr), id(id), line(line) {}
};

struct VarScope {
    std::vector<Variable> vars;
    std::vector<Variable> moved;
};

struct Object {
    Expression *expr;
    llvm::Value *ptr;
};

struct Ownership {
    Resolver *r;
    Method *method;
    std::vector<VarScope> scopes;
    std::vector<Object> objects;
    std::vector<Object> partials;

    Ownership(Resolver *r, Method *m) : r(r), method(m) {}

    void newScope() {
        scopes.push_back(VarScope());
    }
    void newScope(const VarScope &scope) {
        scopes.push_back(scope);
    }

    VarScope dropScope() {
        auto res = scopes.back();
        scopes.pop_back();
        return res;
    }

    bool isDropType(const RType& rt);
    bool isDropType(const Type& type);
    bool isDrop(BaseDecl *decl);

    Variable *find(std::string &name, int id);

    void addPtr(Expression *expr, llvm::Value *ptr) {
        objects.push_back({expr, ptr});
    }

    void bindPtr(Fragment &f, llvm::Value *ptr) {
        for (int i = 0; i < objects.size(); ++i) {
            auto &ob = objects[i];
            if (ob.ptr == ptr) {
                return;
            }
        }
    }

    void add(std::string &name, Type &type, llvm::Value *ptr, int id, int line);

    void add(Fragment &f, Type &type, llvm::Value *ptr) {
        add(f.name, type, ptr, f.id, f.line);
    }

    void add(Param &p, llvm::Value *ptr) {
        add(p.name, p.type.value(), ptr, p.id, p.line);
    }

    void doMove(Expression *expr);

    void doAssign(Expression *lhs, Expression *rhs);
    void endAssign(Expression *lhs);

    //send(expr) //moves expr
    void doMoveCall(Expression *expr);


    void doMoveReturn(Expression *expr);


    Variable *isMoved(SimpleName *sn);


    bool needDrop() { return false; }
};