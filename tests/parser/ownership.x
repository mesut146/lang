import parser/ast
import parser/bridge
import parser/utils
import parser/own_visitor
import std/map

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
    kind: ScopeType;
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

impl VarScope{
    func new(kind: ScopeType, line: i32, exit: Exit): VarScope{
        let scope = VarScope{
            kind: kind,
            id: ++last_scope,
            line: line,
            vars: List<Variable>::new(),
            objects: List<Object>::new(),
            actions: List<Action>::new(),
            exit: exit,
            parent: -1,
            sibling: -1
        };
        return scope;
    }
}

struct Own{
    method: Method*;
    main_scope: i32;
    cur_scope: i32;
    scope_map: Map<i32, VarScope>;
}
impl Own{
    func new(m: Method*): Own{
        let exit = Exit::get_exit_type(m.body.get());
        let main_scope = VarScope::new(ScopeType::MAIN, m.line, exit);
        let res = Own{
            method: m,
            main_scope: main_scope.id,
            cur_scope: main_scope.id,
            scope_map: Map<i32, VarScope>::new()
        };
        res.scope_map.add(main_scope.id, main_scope);
        return res;
    }
    func add_scope(self, kind: ScopeType, line: i32, exit: Exit): i32{
        let scope = VarScope::new(kind, line, exit);
        scope.parent = self.get_scope().id;
        let id = scope.id;
        self.scope_map.add(scope.id, scope);
        self.set_current(id);
        return id;
    }
    func add_scope(self, kind: ScopeType, stmt: Stmt*): i32{
        let exit = Exit::get_exit_type(stmt);
        return self.add_scope(kind, stmt.line, exit);
    }
    func add_scope(self, kind: ScopeType, stmt: Block*): i32{
        let exit = Exit::get_exit_type(stmt);
        return self.add_scope(kind, stmt.line, exit);
    }
    func set_current(self, id: i32){
        assert(id != -1);
        self.cur_scope = id;
    }
    func get_scope(self): VarScope*{
        return self.scope_map.get_ptr(&self.cur_scope).unwrap();
    }
    func add_prm(self, p: Param*){

    }
    func add_var(self, f: Fragment*){
        //self.move(f.rhs);
    }
    func add_iflet_var(self, arg: ArgBind*, fd: FieldDecl*){

    }
    func add_obj(self, expr: Expr*){

    }

    func do_move(self, expr: Expr*){

    }

    func do_return(self, expr: Expr*){
        self.do_move(expr);
    }
    func do_return(self){

    }
    func do_continue(self){

    }
    func do_break(self){
        
    }

    func end_scope(self){
        let scope = self.get_scope();
        if(scope.exit.is_jump()){
            //has own drop
            self.set_current(scope.parent);
            return;
        }
        self.set_current(scope.parent);
    }
    func end_scope_if(self, else_stmt: Stmt*): i32{
        //merge else moves then drop all
        let visitor = OwnVisitor{self};
        visitor.visit(else_stmt);
        let res = self.get_scope().id;
        self.set_current(self.get_scope().parent);
        return res;
    }
}