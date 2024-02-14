#pragma once

#include "parser/Ast.h"

struct Resolver;

struct Variable {
    std::string name;
    int id;
    int line;
    int moveLine = -1;

    Variable(const std::string &name, int id, int line) : name(name), id(id), line(line) {}
};

struct VarScope {
    std::vector<Variable> vars;
    std::vector<Variable> moved;
};

struct Ownership {
    Resolver *r;
    Method *method;
    //std::vector<Variable> moved;
    std::vector<VarScope> scopes;
    //std::vector<Variable> vars;

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

    Variable *find(std::string &name, int id);

    void add(Fragment &f, Type &type) {
        if (type.isPointer()) return;
        if (f.id == -1) {
            throw std::runtime_error("add id");
        }
        scopes.back().vars.push_back(Variable(f.name, f.id, f.line));
    }
    void add(Param &p) {
        if (p.type->isPointer()) {
            return;
        }
        if (p.id == -1) {
            throw std::runtime_error("add id");
        }
        scopes.back().vars.push_back(Variable(p.name, p.id, p.line));
    }

    void doMove(Expression *expr);

    void doAssign(Expression *lhs, Expression *rhs);
    void endAssign(Expression *lhs);

    //send(expr) //moves expr
    void doMoveCall(Expression *expr) {
        doMove(expr);
    }

    void doMoveReturn(Expression *expr){};


    Variable *isMoved(SimpleName *sn);


    bool needDrop() { return false; }
};