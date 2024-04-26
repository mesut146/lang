#pragma once

#include "parser/Ast.h"
#include <llvm/IR/Value.h>
#include <optional>

struct Resolver;
struct Compiler;
struct RType;

//prm or var
struct Variable {
    std::string name;
    Type type;
    llvm::Value *ptr;
    int id;
    int line;
    int scope;
    bool is_self = false;

    Variable(const std::string &name, const Type &type, llvm::Value *ptr, int id, int line, int scope) : name(name), type(type), ptr(ptr), id(id), line(line), scope(scope) {}

    std::string print();
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

    static Object make(Expression *expr, llvm::Value *ptr) {
        return Object{expr, ptr, expr->id, ""};
    }
};

struct Move {
    Variable *lhs = nullptr;//null means transfer
    Expression *lhs_expr = nullptr;
    bool field;
    Object rhs;
    int line;

    bool is_assign() {
        return lhs != nullptr || lhs_expr != nullptr;
    }

    static Move make_var_move(Variable *lhs, const Object &rhs) {
        Move m;
        m.lhs = lhs;
        m.rhs = rhs;
        m.line = rhs.expr->line;
        return m;
    }
    static Move make_var_move(Expression *lhs, const Object &rhs) {
        Move m;
        m.lhs_expr = lhs;
        m.rhs = rhs;
        m.line = rhs.expr->line;
        return m;
    }

    static Move make_transfer(const Object &rhs) {
        Move res;
        res.rhs = rhs;
        res.line = rhs.expr->line;
        return res;
    }
};

enum class ScopeId {
    MAIN,
    IF,
    ELSE,
    WHILE,
    FOR,
};

enum class States {
    MOVED,
    ASSIGNED,
    NONE
};

struct State {
    States state;
    Move *mv;
};

struct Action {
    int line = -1;
    Move mv;
    int scope = -1;

    explicit Action(const Move &mv) : mv(mv) {}
    explicit Action(int scope) : scope(scope) {}
};

struct VarScope {
    ScopeId type;
    int id;
    int line = -1;
    std::vector<int> vars;
    std::vector<Move> moves;
    std::vector<Object> objects;
    std::vector<int> scopes;
    //std::vector<Action> actions;
    bool ends_with_return = false;
    int parent = -1;
    int sibling = -1;
    std::map<int, State> var_states;
    static int last_id;

    explicit VarScope(ScopeId type, int id) : type(type), id(id) {}
};

struct Ownership {
    Compiler *compiler;
    Resolver *r = nullptr;
    Method *method = nullptr;
    VarScope *main_scope = nullptr;
    VarScope *last_scope = nullptr;
    std::map<int, VarScope> scope_map;
    std::map<int, Variable> var_map;
    std::map<std::string, llvm::Function *> protos;
    //std::vector<std::unique_ptr<Impl>> drop_impls;

    //Ownership(Compiler *compiler);

    void init(Compiler *c);

    void init(Method *m);

    void setScope(int id) {
        last_scope = &scope_map.at(id);
    }

    VarScope *newScope(ScopeId type, bool ends_with_return, int parent, int line) {
        int id = ++VarScope::last_id;
        scope_map.insert({id, VarScope(type, id)});
        auto &then = scope_map.at(id);
        then.parent = parent;
        then.ends_with_return = ends_with_return;
        then.line = line;
        last_scope->scopes.push_back(then.id);
        last_scope = &then;
        return &then;
    }

    VarScope &getScope(int id) {
        return scope_map.at(id);
    }
    Variable &getVar(int id) {
        return var_map.at(id);
    }

    //drop vars in this scope
    void endScope(VarScope &s);

    bool isDropType(const RType &rt);
    bool isDropType(const Type &type);
    bool isDropType(Expression *e);
    bool isDrop(BaseDecl *decl);

    void addPtr(Expression *expr, llvm::Value *ptr);

    void check(Expression *expr);

    Variable *add(std::string &name, Type &type, llvm::Value *ptr, int id, int line);

    Variable *addVar(Fragment &f, Type &type, llvm::Value *ptr, Expression *rhs) {
        auto v = add(f.name, type, ptr, f.id, f.line);
        if (v) {
            last_scope->moves.push_back(Move::make_var_move(v, Object::make(rhs)));
        }
        return v;
    }

    Variable *addPrm(Param &p, llvm::Value *ptr, bool is_self) {
        auto res = add(p.name, p.type.value(), ptr, p.id, p.line);
        if (res) {
            res->is_self = is_self;
        }
        return res;
    }

    void doMove(Expression *expr);
    std::pair<Move *, VarScope *> is_assignable(Expression *expr);

    void endAssign(Expression *lhs, Expression *rhs);
    void beginAssign(Expression *lhs, llvm::Value *ptr);

    //send(expr) //moves expr
    void doMoveCall(Expression *expr);

    void doMoveReturn(Expression *expr);

    void moveToField(Expression *expr);

    bool needDrop() { return false; }

    void doReturn(int line);

    void drop(Expression *expr, llvm::Value *ptr);
    void drop(Variable &v);

    std::vector<VarScope *> rev_scopes();

    void end_branch(VarScope &scope);

    void call_drop_force(Type &type, llvm::Value *ptr);
    void call_drop(Type &type, llvm::Value *ptr);

    void jump_continue();

    void jump_break();
};