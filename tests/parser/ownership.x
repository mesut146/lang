import parser/ast
import parser/bridge
import parser/utils
import parser/own_visitor
import parser/compiler
import parser/resolver
import parser/compiler_helper
import parser/debug_helper
import parser/printer
import std/map
import std/stack

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

#derive(Debug)
enum StateType {
    NONE,
    MOVED,
    MOVED_PARTIAL,
    ASSIGNED
}

enum Action {
    MOVE(mv: Move),
    SCOPE(id: i32, line: i32)
}

struct Lhs{
    expr: Expr*;
}

struct Move{
    lhs: Option<Lhs>;
    rhs: Expr*;
    line: i32;
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
    compiler: Compiler*;
    method: Method*;
    main_scope: i32;
    cur_scope: i32;
    scope_map: Map<i32, VarScope>;
}
impl Own{
    func new(c: Compiler*, m: Method*): Own{
        let exit = Exit::get_exit_type(m.body.get());
        let main_scope = VarScope::new(ScopeType::MAIN, m.line, exit);
        let res = Own{
            compiler: c,
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
    //register var & obj
    func is_drop_type(self, type: Type*): bool{
        let helper = DropHelper{self.compiler.get_resolver()};
        return helper.is_drop_type(type);
    }
    func add_prm(self, p: Param*, ptr: Value*){
        if(!self.is_drop_type(&p.type)) return;
        let var = Variable{
            name: p.name.clone(),
            type: p.type.clone(),
            ptr: ptr,
            id: p.id,
            line: p.line,
            scope: self.get_scope().id,
            is_self: p.is_self
        };
        self.get_scope().vars.add(var);
    }
    func add_var(self, f: Fragment*, ptr: Value*){
        let rt = self.compiler.get_resolver().visit(f);
        if(!self.is_drop_type(&rt.type)) return;
        let var = Variable{
            name: f.name.clone(),
            type: rt.type.clone(),
            ptr: ptr,
            id: f.id,
            line: f.line,
            scope: self.get_scope().id,
            is_self: false
        };
        self.get_scope().vars.add(var);
        self.do_move(&f.rhs);
    }
    func add_iflet_var(self, arg: ArgBind*, fd: FieldDecl*, ptr: Value*){
        if(arg.is_ptr) return;
        if(!self.is_drop_type(&fd.type)) return;
        let var = Variable{
            name: arg.name.clone(),
            type: fd.type.clone(),
            ptr: ptr,
            id: arg.id,
            line: arg.line,
            scope: self.get_scope().id,
            is_self: false
        };
        self.get_scope().vars.add(var);
    }
    func add_obj(self, expr: Expr*, ptr: Value*, type: Type*){
        if(!self.is_drop_type(type)) return;
        let obj = Object{
            expr: expr,
            ptr: ptr,
            id: expr.id,
            name: expr.print()
        };
        self.get_scope().objects.add(obj);
        //panic("add_obj {}: {} in {}", expr, type, printMethod(self.method));
    }

    func do_move(self, expr: Expr*){
        let mv = Move{
            lhs: Option<Lhs>::new(),
            rhs: expr,
            line: expr.line
        };
        let act = Action::MOVE{mv};
        self.get_scope().actions.add(act);
    }

    func do_return(self, expr: Expr*){
        self.do_move(expr);
        self.do_return();
    }
    func get_state(self, expr: Expr*, scope: VarScope*): StateType{
        for(let i = 0;i < scope.actions.len();++i){
            let act = scope.actions.get_ptr(i);
            if let Action::MOVE(mv*) = (act){
                if(mv.rhs.id == expr.id){
                    return StateType::MOVED;
                }
            }
        }
        return StateType::NONE;
    }
    func do_return(self){
        //drop
        let scope = self.get_scope();
        for(let i = 0;i < scope.objects.len();++i){
            let obj = scope.objects.get_ptr(i);
            let state = self.get_state(obj.expr, scope);
            if(state is StateType::MOVED){
                continue;
            }
            panic("drop obj {} in {} state:{}", obj.expr, self.method, state);
        }
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
        let visitor = OwnVisitor{self, -1};
        visitor.visit(else_stmt);
        let res = self.get_scope().id;
        self.set_current(self.get_scope().parent);
        return res;
    }
}