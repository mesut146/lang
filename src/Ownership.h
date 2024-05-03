#pragma once

#include "parser/Ast.h"
#include "TypeUtils.h"
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

struct Lhs {
    Expression *expr;
    int var_id = -1;

    explicit Lhs(Expression *expr) : expr(expr) {}
    explicit Lhs(Expression *expr, int var_id) : expr(expr), var_id(var_id) {}

    bool is_var() const {
        return var_id != -1;
    }
};

struct Move {
    std::optional<Lhs> lhs;
    bool field;
    Object rhs;
    int line;
    bool is_transfer = false;

    bool is_assign() {
        return !is_transfer;
    }

    static Move make_var_move(Expression *lhs, Variable *lhs_var, const Object &rhs) {
        Move m;
        m.lhs = Lhs(lhs, lhs_var->id);
        m.rhs = rhs;
        m.line = rhs.expr->line;
        return m;
    }
    static Move make_var_move(Expression *lhs, const Object &rhs) {
        Move m;
        m.lhs = Lhs(lhs);
        m.rhs = rhs;
        m.line = rhs.expr->line;
        return m;
    }

    static Move make_transfer(const Object &rhs) {
        Move res;
        res.rhs = rhs;
        res.line = rhs.expr->line;
        res.is_transfer = true;
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
    NONE,
    MOVED,
    MOVED_PARTIAL,
    ASSIGNED,
};

struct State {
    States state;
    Move *mv;

    bool is_moved() {
        return state == States::MOVED;
    }
    bool is_moved_partial() {
        return state == States::MOVED_PARTIAL;
    }
    bool is_none() {
        return state == States::NONE;
    }
};

struct Action {
    int line = -1;
    Move mv;
    int scope_decl = -1;

    explicit Action(const Move &mv) : mv(mv) {}
    explicit Action(int scope_decl) : scope_decl(scope_decl) {}

    bool is_scope_decl() {
        return scope_decl != -1;
    }

    bool is_move() {
        return scope_decl == -1;
    }
};

struct VarScope {
    ScopeId type;
    int id;
    int line = -1;
    std::vector<int> vars;
    std::vector<Object> objects;
    std::vector<Action> actions;
    Exit exit;
    int parent = -1;
    int sibling = -1;
    std::map<int, State> var_states;
    static int last_id;

    explicit VarScope(ScopeId type, int id) : type(type), id(id) {}

    std::string print_info();
    
};

struct Compiler;

struct DropProtos {
    std::map<std::string, llvm::Function *> protos;
    Compiler *compiler;

    //DropProtos(Compiler *compiler) : compiler(compiler) {}

    void call_drop_force(Type &type, llvm::Value *ptr);
};

struct DropHelper {
    Resolver *r;

    DropHelper(Resolver *r) : r(r) {}

    bool isDropType(const Type &type);
    bool isDropType(const RType &rt);
    static bool isDropType(const Type &type, Resolver *r) {
        return DropHelper(r).isDropType(type);
    }
    static bool isDropType(const RType &type, Resolver *r) {
        return DropHelper(r).isDropType(type);
    }
    bool isDrop(BaseDecl *decl);
};

struct Ownership {
    Compiler *compiler;
    Resolver *r = nullptr;
    Method *method = nullptr;
    VarScope *main_scope = nullptr;
    VarScope *last_scope = nullptr;
    std::map<int, VarScope> scope_map;
    std::map<int, Variable> var_map;
    DropProtos protos;

    void init(Compiler *c);

    void init(Method *m);

    void setScope(int id) {
        last_scope = &scope_map.at(id);
    }

    VarScope *newScope(ScopeId type, const Exit &exit, int parent, int line) {
        int id = ++VarScope::last_id;
        scope_map.insert({id, VarScope(type, id)});
        auto &then = scope_map.at(id);
        then.parent = parent;
        then.exit = exit;
        then.line = line;
        last_scope->actions.push_back(Action(then.id));
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

    bool isDropType(Expression *e);

    void addPtr(Expression *expr, llvm::Value *ptr);

    void check(Expression *expr);

    Variable *add(std::string &name, Type &type, llvm::Value *ptr, int id, int line);

    Variable *addVar(Fragment &f, Type &type, llvm::Value *ptr, Expression *rhs) {
        auto v = add(f.name, type, ptr, f.id, f.line);
        if (v != nullptr) {
            auto act = Action(Move::make_var_move(nullptr, v, Object::make(rhs)));
            last_scope->actions.push_back(act);
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
    void check_assignable(Expression *expr);

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