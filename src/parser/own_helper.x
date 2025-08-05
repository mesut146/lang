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

import parser/own_model
import parser/ownership

func is_drop_method(method: Method*): bool{
    if(method.name.eq("drop") && method.parent.is_impl()){
        let imp =  method.parent.as_impl();
        return imp.trait_name.is_some() && imp.trait_name.get().eq("Drop");
    }
    return false;
}

impl VarScope{
    func print(self, own: Own*): String{
        let f = Fmt::new();
        self.debug(&f, own, "");
        return f.unwrap();
    }
    func print_info(self): String{
        let f = Fmt::new();
        f.print("VarScope{");
        f.print(&self.kind);
        f.print(", line: ");
        f.print(&self.line);
        f.print("}");
        return f.unwrap();
    }
    func debug(self, f: Fmt*, own: Own*, indent: str){
        f.print(indent);
        f.print("VarScope ");
        f.print(&self.kind);
        f.print(", line: ");
        f.print(&self.line);
        f.print("{");
        for var_id in &self.vars{
            let var = own.get_var(*var_id);
            f.print("\n");
            f.print(indent);
            f.print("  let ");
            f.print(&var.name);
            f.print(": ");
            f.print(&var.type);
            f.print(", line: ");
            f.print(&var.line);
        }
        for obj in &self.objects{
            f.print("\n");
            f.print(indent);
            f.print("  obj line: ");
            f.print(&obj.expr.line);
            f.print(", ");
            f.print(obj.expr);
        }
        for pair in &self.state_map{
            f.print("\n");
            f.print(indent);
            f.print("  state(");
            pair.a.debug(f);
            f.print(")");
            f.print("=");
            pair.b.debug(f);
        }
        f.print("\n");
        f.print(indent);
        f.print("}");
    }
}

impl Debug for Move{
    func debug(self, f: Fmt*){
        f.print("Move{");
        if(self.lhs.is_some()){
            f.print(self.lhs.get());
            f.print(" = ");
        }
        Debug::debug(&self.rhs, f);
        f.print("}");
    }
}

impl Debug for State{
    func debug(self, f: Fmt*){
        self.kind.debug(f);
    }
}

impl Debug for Variable{
    func debug(self, f: Fmt*){
        f.print("Variable{");
        f.print(&self.name);
        f.print(": ");
        f.print(&self.type);
        f.print(", line: ");
        f.print(&self.line);
        f.print("}");
    }
}
impl Debug for Rhs{
    func debug(self, f: Fmt*){
        match self{
            Rhs::EXPR(e) => {
                f.print("Rhs::EXPR{");
                f.print(*e);
                f.print("}");
            },
            Rhs::VAR(v) => {
                //f.print("Rhs::VAR{");
                f.print(v);
                //f.print("}");
            },
            Rhs::FIELD(scp, name) => {
                f.print("Rhs::FIELD{");
                f.print(scp);
                f.print(", ");
                f.print(name);
                f.print("}");
            },
        }
    }
}
impl Clone for Rhs{
    func clone(self): Rhs{
        match self{
            Rhs::EXPR(e) => return Rhs::EXPR{*e},
            Rhs::VAR(v) => return Rhs::VAR{v.clone()},
            Rhs::FIELD(scp, name) => return Rhs::FIELD{scp: scp.clone(), name: name.clone()},
        }
    }
}
impl Eq for Rhs{
    func eq(self, other: Rhs*): bool{
        let s1 = Fmt::str(self);
        let s2 = Fmt::str(other);
        let res = s1.eq(&s2);
        s1.drop();
        s2.drop();
        return res;
    }
}

impl Debug for Moved{
    func debug(self, f: Fmt*){
        if(self.var.is_some()){
            //f.print("var{");
            self.var.get().debug(f);
            //f.print("}");
        }else{
            f.print(self.expr);
        }
    }
}