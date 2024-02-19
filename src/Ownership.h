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

struct VarScope {
    std::vector<Variable> vars;
    std::vector<Variable> moved;

    std::optional<VarScope> next_scope;

    VarScope(const VarScope &other) {
        vars = other.vars;
        moved = other.moved;
        //next_scope = other.next_scope;
    }
    VarScope(VarScope &&other) {
    }

    VarScope operator=(VarScope &rhs) {
        return *this;
    }
};

struct Object {
    Expression *expr;
    llvm::Value *ptr;
};

struct Ownership {
    Compiler *compiler;
    Resolver *r;
    Method *method;
    VarScope scope;
    VarScope *last_scope = nullptr;
    std::vector<Object> objects;
    std::vector<Object> partials;

    Ownership(Compiler *compiler, Method *m);


    void newScope() {
        //scope.next_scope = std::move(std::make_optional<VarScope>());
        scope.next_scope.emplace();
    }

    void newScope(VarScope &s) {
        last_scope->next_scope = s;
    }

    VarScope dropScope() {
        /*auto prev = &scope;
        auto cur = &prev->next_scope.value();
        for (true) {
            if (cur->next_scope.has_value()) {

            } else {
                auto res = prev->next_scope.value();
                prev->next_scope.reset();
                return res;
            }
        }*/
    }

    bool isDropType(const RType &rt);
    bool isDropType(const Type &type);
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

    void check(Expression *expr);

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

    void moveToField(Expression *expr);


    Variable *isMoved(SimpleName *sn);

    bool needDrop() { return false; }

    void doReturn();

    void drop(Expression *expr, llvm::Value *ptr);
};