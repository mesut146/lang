import parser/ast
import parser/bridge
import parser/utils

static last_scope: i32 = 0;

//prm or var
struct Variable {
    name: String;
    type: Type;
    ptr: Value*;
    id: i32;
    line: i32;
    scope: i32;
    is_self: bool;
}
//dropable
struct Object {
    expr: Expr*;
    ptr: Value*;
    id: i32;          //prm
    name: String;     //prm
}

enum ScopeType {
    MAIN,
    IF,
    ELSE,
    WHILE,
    FOR
}

struct VarScope{
    type: ScopeType;
    id: i32;
    line: i32;
    vars: List<Variable>;
    objects: List<Object>;
    actions: List<Action>;
    exit: Exit;
    parent: i32;
    sibling: i32;
}

enum States {
    NONE,
    MOVED,
    MOVED_PARTIAL,
    ASSIGNED
}

enum Action {
    MOVE(mv: Move, line: i32),
    SCOPE(id: i32, line: i32)
}

struct Lhs{
    expr: Expr*;
}

struct Move{
    lhs: Lhs;
    rhs: Object;
    line: i32;
    is_assign: bool;
}

struct Own{
    method: Method*;
    main_scope: i32;
    cur_scope: VarScope*;
    scope_map: Map<i32, VarScope>;
}
impl Own{
    func new(m: Method*): Own{
        let main_scope = make_scope(ScopeType::MAIN, m.line, exit);
        return Own{
            method: m,
            main_scope: main_scope.id;
            cur_scope: &main_scope,
            scope_map: Map::new(),
        };
    }
    func make_scope(type: ScopeType, line: i32, exit: Exit): VarScope{
        let scope = VarScope{
            type: type,
            id: ++last_scope,
            line: line,
            vars: List<Variable>::new(),
            objects: List<Object>::new(),
            actions: List<Action>::new(),
            exit: exit,
            parent: -1,
            sibling: -1,
        };
        return scope;
    }
    func add_prm(self, p: Param*){

    }
    func add_var(self, f: Fragment*){
        //self.move(f.rhs);
    }
    func add_if_var(self, arg: ArgBind*, fd: FieldDecl*){

    }
    func add_obj(self, expr: Expr*){

    }
}