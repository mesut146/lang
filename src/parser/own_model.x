import std/map
import std/hashmap
import std/stack

import ast/ast
import ast/utils
import ast/printer

import resolver/resolver
import resolver/method_resolver
import resolver/derive
import resolver/exit

import parser/ownership
import parser/own_visitor
import parser/own_model
import parser/own_helper

import backend/bridge

#derive(Debug)
struct LLVMPtr{
    ptr: Value*;
}
impl LLVMPtr{
    func new(ptr: Value*): LLVMPtr{
        return LLVMPtr{ptr: ptr};
    }    
}

//prm or var
struct Variable {
    name: String;
    type: Type;
    ptr: LLVMPtr;
    id: i32;
    line: i32;
    scope: i32;
    is_self: bool;
    //a captured parameter of a generated lambda method: borrowed from the
    //closure object, so it is never dropped here and cannot be moved out
    //(see Param.is_captured and doc/closures.txt section 9).
    is_captured: bool;
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
            is_self: self.is_self,
            is_captured: self.is_captured
        };
    }
}

//dropable
#derive(Debug)
struct Object {
    expr: Expr*;
    ptr: LLVMPtr;
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
//A move of drop-typed data out through a pointer, awaiting heal by
//reassignment in the same scope. Unhealed leftovers error at scope end
//(see check_ptr_moves): moves can't dangle, borrows stay free.
struct PtrMove{
    place: String;
    line: i32;
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
    ptr_left: List<PtrMove>;
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
            pending_parent: HashMap<i32, StateType>::new(),
            ptr_left: List<PtrMove>::new()
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

//match payload binding record: which named scrutinee it was copied
//from, the scrutinee's pre-bind state, and the bind line. At arm end,
//if no binding escaped and the scrutinee is otherwise untouched, the
//bind marks are rolled back: unmoved bindings are suppressed (their
//bytes alias the scrutinee) and the scrutinee drops normally. No leak,
//no false use-after-move for inspect-only arms.
struct BindInfo{
    scr: i32;
    pre: StateType;
    line: i32;
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
    EXPR{e: Expr*},
    VAR{v: Variable},
    FIELD{scp: Variable, name: String},
    //A constant index into a local array: an element place, tracked exactly
    //like a field (see Rhs::new below). Moving one element out suppresses the
    //array's own drop; check_partial then requires every drop element to
    //move, mirroring the all-fields rule for structs.
    INDEX{scp: Variable, idx: i32}
}
enum Droppable{
    VAR{var: Variable*},
    OBJ{obj: Object*}
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
            let scp_rt = own.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_some()){
                let scp_var = own.get_var(scp_rt.vh.get().id);
                return Moved{expr, Option::new(scp_var.clone())};
            }
        }*/
        let rt = own.get_resolver().visit(expr);
        if(rt.vh.is_some()){
            let var = own.get_var(rt.vh.get().id);
            return Moved{expr, Option::new(var.clone())};
        }
        return Moved{expr, Option<Variable>::new()};
    }
}

impl Rhs{
    func new(scope: Variable, name: String): Rhs{
        return Rhs::FIELD{scope, name};
    }
    func new(scope: Variable, idx: i32): Rhs{
        return Rhs::INDEX{scope, idx};
    }
    func new(expr: Expr*, own: Own*): Rhs{
        if let Expr::Access(scp, name)=expr{
            let scp_rt = own.get_resolver().visit(scp.get());
            if(scp_rt.vh.is_some()){
                let scp_var = own.get_var(scp_rt.vh.get().id);
                return Rhs::FIELD{scp_var.clone(), name.clone()};
            }
            //unsafe deref is transparent for place identity: `ptr::deref!(p).f`
            //names the same place as `p.f`, so drop-on-assign and move tracking
            //apply even though the raw deref macro carries no vh of its own.
            //(bare `ptr::deref!(p)` stays EXPR/untracked, as documented.)
            if let Expr::MacroCall(mc) = scp.get(){
                if(Utils::is_call(mc, "ptr", "deref") && mc.args.len() > 0){
                    let irt = own.get_resolver().visit(mc.args.get(0));
                    if(irt.vh.is_some() && own.var_map.get(&irt.vh.get().id).is_some()){
                        let iv = own.get_var(irt.vh.get().id);
                        return Rhs::FIELD{iv.clone(), name.clone()};
                    }
                }
            }
        }
        //A *constant* index into a local array is a place like a field
        //(`arr[0]` <=> field "0"): the element can be moved out and dropped
        //independently, and once any element moved the array's own drop is
        //suppressed (check_partial then requires all drop elements to move,
        //the same all-fields rule as for structs). A dynamic index, a slice
        //(`arr[a..b]`), or a pointer base has no place state and stays
        //Rhs::EXPR, so do_move keeps refusing moves out of it.
        if let Expr::ArrAccess(aa) = expr{
            //Only a *plain local array* base gets a tracked element place:
            //`arr[0]`. A slice, a pointer, a nested array, or a field-typed
            //base stays untracked (Rhs::EXPR) and is refused below.
            if(aa.arr.get() is Expr::Name){
                let opt = own.const_index(aa);
                if(opt.is_some()){
                    let art = own.get_resolver().visit(aa.arr.get());
                    if(art.type.is_array()){
                        if(art.vh.is_some() && own.var_map.get(&art.vh.get().id).is_some()){
                            let av = own.get_var(art.vh.get().id);
                            return Rhs::INDEX{scp: av.clone(), idx: opt.unwrap()};
                        }
                    }
                }
            }
        }
        let rt = own.get_resolver().visit(expr);
        if(rt.vh.is_some() && (expr is Expr::Name || expr is Expr::Unary)){
            let var = own.get_var(rt.vh.get().id);
            return Rhs::VAR{var.clone()};
        }
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
                return res;
            }
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
        return lhs2.eq(lhs, own.get_resolver());
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
