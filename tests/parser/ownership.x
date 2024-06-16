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

func is_drop_method(method: Method*): bool{
    if(method.name.eq("drop") && method.parent.is_impl()){
        let imp =  method.parent.as_impl();
        return imp.trait_name.is_some() && imp.trait_name.get().eq("Drop");
    }
    return false;
}

//prm or var
#derive(Debug)
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
#derive(Debug)
struct Object {
    expr: Expr*;
    ptr: Value*;
    id: i32;          //prm
    name: String;     //prm
}
#derive(Debug)
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

impl VarScope{
    func print(self, own: Own*): String{
        let f = Fmt::new();
        self.debug(&f, own, "");
        return f.unwrap();
    }
    func debug(self, f: Fmt*, own: Own*, indent: str){
        f.print(indent);
        f.print("VarScope ");
        f.print(&self.kind);
        f.print(", line: ");
        f.print(&self.line);
        f.print("{");
        for(let i=0;i<self.vars.len();++i){
            let var = self.vars.get_ptr(i);
            f.print("\n");
            f.print(indent);
            f.print("let ");
            f.print(&var.name);
            f.print(": ");
            f.print(&var.type);
            f.print(", line: ");
            f.print(&var.line);
        }
        for(let i=0;i<self.objects.len();++i){
            let obj = self.objects.get_ptr(i);
            f.print("\n");
            f.print(indent);
            f.print("obj line: ");
            f.print(&obj.expr.line);
            f.print(", ");
            f.print(obj.expr);
        }
        for(let i=0;i<self.actions.len();++i){
            let act = self.actions.get_ptr(i);
            if let Action::SCOPE(id, line)=(act){
                let ch_scope = own.get_scope(id);
                let id2 = format("{} ", indent);
                f.print("\n");
                ch_scope.debug(f, own, id2.str());
                id2.drop();
            }else{
                f.print("\n");
                f.print(indent);
                f.print("act ");
                f.print(act);
            }
        }
        f.print("\n");
        f.print(indent);
        f.print("}");
    }
}

#derive(Debug)
enum StateType {
    NONE,
    MOVED(line: i32),
    MOVED_PARTIAL,
    ASSIGNED
}

enum Action {
    MOVE(mv: Move),
    SCOPE(id: i32, line: i32)
}
impl Debug for Action{
    func debug(self, f: Fmt*){
        f.print("Action::");
        if let Action::MOVE(mv*)=(self){
            f.print("MOVE{");
            f.print(mv.rhs);
            f.print(" line: ");
            f.print(&mv.line);
            f.print("}");
        }
        if let Action::SCOPE(id, line)=(self){
            f.print("SCOPE{");
            f.print(&id);
            f.print(", ");
            f.print(&line);
            f.print("}");
        }
    }
}

#derive(Debug)
struct Lhs{
    expr: Expr*;
}
#derive(Debug)
enum Rhs{
    EXPR(e: Expr*),
    VAR(v: Variable*)
}
impl Rhs{
    func get_var(self): Variable*{
        if let Rhs::VAR(v)=(self){
            return v;
        }
        panic("");
    }
    func get_expr(self): Expr*{
        if let Rhs::EXPR(e)=(self){
            return e;
        }
        panic("");
    }
    func get_id(self): i32{
        if let Rhs::EXPR(e)=(self){
            return e.id;
        }
        if let Rhs::VAR(v)=(self){
            return v.id;
        }
        panic("");
    }
    func is_vh(self, vh: VarHolder*, compiler: Compiler*): bool{
        if let Rhs::EXPR(e)=(self){
            let rt = compiler.get_resolver().visit(e);
            if(rt.vh.is_some()){
                let res = rt.vh.get().id == vh.id;
                rt.drop();
                return res;
            }
            rt.drop();
            return false;
        }
        return self.get_var().id == vh.id;
    }
}
#derive(Debug)
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

enum Droppable{
    VAR(var: Variable*),
    OBJ(obj: Object*)
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
        self.get_scope().actions.add(Action::SCOPE{id, line});        
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
    func get_scope(self, id: i32): VarScope*{
        return self.scope_map.get_ptr(&id).unwrap();
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
        let type = self.compiler.get_resolver().visit(expr);
        if(!self.is_drop_type(&type.type)) return;
        let mv = Move{
            lhs: Option<Lhs>::new(),
            rhs: expr,
            line: expr.line
        };
        print("move {} line:{}\n", mv.rhs, mv.line);
        let act = Action::MOVE{mv};
        self.get_scope().actions.add(act);
    }

    func do_return(self, expr: Expr*){
        self.do_move(expr);
        print("do_return {}\n", expr.line);
        self.do_return();
    }
    func get_state(self, rhs: Rhs, scope: VarScope*, look_parent: bool): StateType{
        for(let i = 0;i < scope.actions.len();++i){
            let act = scope.actions.get_ptr(i);
            if let Action::MOVE(mv*) = (act){
                if(rhs is Rhs::EXPR){
                    //tmp obj moved immediatly
                    if(mv.rhs.id == rhs.get_id()){
                        return StateType::MOVED{mv.line};
                    }
                }
                let mv_rt = self.compiler.get_resolver().visit(mv.rhs);
                if(mv_rt.vh.is_some()){
                    if(rhs.is_vh(mv_rt.vh.get(), self.compiler)){
                        return StateType::MOVED{mv.line};
                    }
                }else{
                    if(mv.rhs.id == rhs.get_id()){
                        return StateType::MOVED{mv.line};
                    }
                }
            }
        }
        if(look_parent && scope.parent != -1){
            let parent = self.get_scope(scope.parent);
            return self.get_state(rhs, parent, true);
        }
        return StateType::NONE;
    }
    func check(self, expr: Expr*){
        let scope = self.get_scope();
        let rhs = Rhs::EXPR{expr};
        let state = self.get_state(rhs, scope, true);
        //print("check {} line:{} {}\n", expr, expr.line, state);
        if let StateType::MOVED(line)=(state){
            self.compiler.get_resolver().err(expr, format("use after move in {}", line));
        }
    }

    func get_outer_vars(self, scope: VarScope*, list: List<Droppable>*){
        for(let i = 0;i < scope.vars.len();++i){
            let var = scope.vars.get_ptr(i);
            list.add(Droppable::VAR{var});
        }
        for(let i = 0;i < scope.objects.len();++i){
            let obj = scope.objects.get_ptr(i);
            list.add(Droppable::OBJ{obj});
        }
        if(scope.parent != -1){
            let parent = self.get_scope(scope.parent);
            self.get_outer_vars(parent, list);
        }
    }
    func drop_obj(self, obj: Object*, scope: VarScope*){
        let rhs = Rhs::EXPR{obj.expr};
        let state = self.get_state(rhs, scope, true);
        if(state is StateType::MOVED){
            return;
        }
        panic("drop_obj {} state: {} in\n{}", obj.expr, state, printMethod(self.method));
    }
    func drop_var(self, var: Variable*, scope: VarScope*){
        let rhs = Rhs::VAR{var};
        let state = self.get_state(rhs, scope, true);
        if(state is StateType::MOVED){
            return;
        }
        if(var.is_self && is_drop_method(self.method)){
            return;
        }
        print("drop_var {} state: {} in {}\n{}\n", var, state, self.method.parent, printMethod(self.method));
        print("{}\n", scope.print(self));
        self.compiler.get_resolver().err(var.line, "".str());
    }
    func drop_return(self, scope: VarScope*){
        print("drop_return {} line: {}\n", scope.kind, scope.line);
        let drops = List<Droppable>::new();
        self.get_outer_vars(scope, &drops);
        for(let i = 0;i < drops.len();++i){
            let dr = drops.get_ptr(i);
            if let Droppable::OBJ(obj)=(dr){
                self.drop_obj(obj, scope);
            }
            if let Droppable::VAR(var)=(dr){
                self.drop_var(var, scope);
            }
        }
    }
    func do_return(self){
        let scope = self.get_scope();
        self.drop_return(scope);
        /*while(scope.parent != -1){
            let parent = self.get_scope(scope.parent);
            self.drop_return(parent);
            scope = parent;
        }*/
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