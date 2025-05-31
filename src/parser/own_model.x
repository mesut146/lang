import std/map
import std/hashmap
import std/stack

import ast/ast
import ast/utils
import ast/printer

import parser/bridge
import parser/ownership
import parser/own_visitor
import parser/own_model
import parser/own_helper
import parser/compiler
import parser/resolver
import parser/compiler_helper
import parser/method_resolver
import parser/debug_helper
import parser/derive
import parser/exit

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
impl Variable{
    func clone(self): Variable{
        return Variable{
            name: self.name.clone(),
            type: self.type.clone(),
            ptr: self.ptr,
            id: self.id,
            line: self.line,
            scope: self.scope,
            is_self: self.is_self
        };
    }
}

//dropable
#derive(Debug)
struct Object {
    expr: Expr*;
    ptr: Value*;
    id: i32;          //prm
    name: String;     //prm
    scope: i32;
}
#derive(Debug)
enum ScopeType {
    MAIN,
    IF,
    ELSE,
    WHILE,
    FOR,
    MATCH_CASE
}
struct VarScope{
    kind: ScopeType;
    id: i32;
    line: i32;
    vars: List<i32>;
    objects: List<Object>;
    exit: Exit;
    parent: i32;
    sibling: i32;
    is_empty: bool;
    state_map: HashMap<Rhs, StateType>; //var_id -> StateType
    pending_parent: HashMap<i32, StateType>; //var_id -> StateType
}
impl VarScope{
    func new(kind: ScopeType, line: i32, exit: Exit): VarScope{
        let scope = VarScope{
            kind: kind,
            id: ++last_scope,
            line: line,
            vars: List<i32>::new(),
            objects: List<Object>::new(),
            exit: exit,
            parent: -1,
            sibling: -1,
            is_empty: false,
            state_map: HashMap<Rhs, StateType>::new(),
            pending_parent: HashMap<i32, StateType>::new()
        };
        return scope;
    }
}

#derive(Debug, Clone)
enum StateType {
    NONE,
    MOVED(line: i32),
    MOVED_PARTIAL,
    ASSIGNED
}

struct State{
    kind: StateType;
    scope: VarScope*;
}

struct Move{
    lhs: Option<Moved>;
    rhs: Moved;
    line: i32;
}
struct Moved{
    expr: Expr*;
    var: Option<Variable>;
    //field: Option<String>;
}

enum Rhs{
    EXPR(e: Expr*),
    VAR(v: Variable),
    FIELD(scp: Variable, name: String)
}
enum Droppable{
    VAR(var: Variable*),
    OBJ(obj: Object*)
}

impl Hash for Rhs{
    func hash(self): i64{
        /*match self{
            Rhs::EXPR(e) => e.id as i64,
            Rhs::VAR(v*) => v.id as i64,
            Rhs::FIELD(scp*,name*) => scp.id * 31 + name.hash()
        }*/
        let s = Fmt::str(self);
        let h = s.hash();
        s.drop();
        return h;
    }
}

impl State{
    func new(kind: StateType, scope: VarScope*): State{
        return State{kind, scope};
    }
    func is_moved(self): bool{
        return self.kind is StateType::MOVED || self.kind is StateType::MOVED_PARTIAL;
    }
    func is_assigned(self): bool{
        return self.kind is StateType::ASSIGNED;
    }
    func is_none(self): bool{
        return self.kind is StateType::NONE;
    }
    func get_line(self): i32{
        if let StateType::MOVED(line)=self.kind{
            return line;
        }
        panic("not move");
    }
}
impl StateType{
    func is_moved(self): bool{
        return self is StateType::MOVED || self is StateType::MOVED_PARTIAL;
    }
    func is_assigned(self): bool{
        return self is StateType::ASSIGNED;
    }
    func is_none(self): bool{
        return self is StateType::NONE;
    }
}

impl Moved{
    func new(expr: Expr*, own: Own*): Moved{
        /*if let Expr::Access(scp*, name*)=expr{
            let scp_rt = own.compiler.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_some()){
                let scp_var = own.get_var(scp_rt.vh.get().id);
                return Moved{expr, Option::new(scp_var.clone())};
            }
        }*/
        let rt = own.compiler.get_resolver().visit(expr);
        if(rt.vh.is_some()){
            let var = own.get_var(rt.vh.get().id);
            rt.drop();
            return Moved{expr, Option::new(var.clone())};
        }
        rt.drop();
        return Moved{expr, Option<Variable>::new()};
    }
}

impl Rhs{
    func new(scope: Variable, name: String): Rhs{
        return Rhs::FIELD{scope, name};
    }
    func new(expr: Expr*, own: Own*): Rhs{
        if let Expr::Access(scp, name)=expr{
            let scp_rt = own.compiler.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_some()){
                let scp_var = own.get_var(scp_rt.vh.get().id);
                scp_rt.drop();
                return Rhs::FIELD{scp_var.clone(), name.clone()};
            }
            scp_rt.drop();
        }
        let rt = own.compiler.get_resolver().visit(expr);
        if(rt.vh.is_some() && (expr is Expr::Name || expr is Expr::Unary)){
            let var = own.get_var(rt.vh.get().id);
            rt.drop();
            return Rhs::VAR{var.clone()};
        }
        rt.drop();
        return Rhs::EXPR{expr};
    }
    func new(var: Variable): Rhs{
        return Rhs::VAR{var};
    }
    func get_var(self): Variable*{
        if let Rhs::VAR(v)=self{
            return v;
        }
        panic("");
    }
    func get_expr(self): Expr*{
        if let Rhs::EXPR(e)=self{
            return *e;
        }
        panic("");
    }
    func get_id(self): i32{
        if let Rhs::EXPR(e)=self{
            return (*e).id;
        }
        if let Rhs::VAR(v)=self{
            return v.id;
        }
        panic("{:?}", self);
    }
    func is_vh(self, vh: VarHolder*, resolver: Resolver*): bool{
        if let Rhs::EXPR(e)=self{
            let rt = resolver.visit(*e);
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
    func eq(self, other: Moved*, resolver: Resolver*): bool{
        if let Rhs::EXPR(e)=self{
            if((*e).id == other.expr.id){
                return true;
            }
            return false;
        }
        if(other.var.is_some()){
            return self.get_var().id == other.var.get().id;
        }
        return false;
    }
}

impl Move{
    func is_lhs(self, lhs2: Rhs*, own: Own*): bool{
        if(self.lhs.is_none()){
            return false;
        }
        let lhs: Moved* = self.lhs.get();
        return lhs2.eq(lhs, own.compiler.get_resolver());
    }
    func is_rhs(self, other: Rhs*, own: Own*): bool{
        if(self.rhs.var.is_none()){
            if(other is Rhs::EXPR){
                return self.rhs.expr.id == other.get_expr().id;
            }
            return false;
        }
        //self is var
        if(other is Rhs::VAR){
            let var: Variable* = self.rhs.var.get();
            return var.id == other.get_var().id;
        }
        return false;
    }
}

impl Droppable{
    func as_var(self): Variable*{
        match self{
            Droppable::VAR(v) => return *v,
            _ => panic("");
        }
    }
    func drop_local(self, scope: VarScope*, line: i32, own: Own*): bool{
        match self{
            Droppable::OBJ(obj) => {
                if((*obj).scope == scope.id){
                    own.drop_obj(*obj, scope, line);
                    return true;
                }
                return false;
            },
            Droppable::VAR(var) => {
                if((*var).scope == scope.id){
                    own.drop_var(*var, scope, line);
                    return true;
                }
                return false;
            }
        }
    }
}