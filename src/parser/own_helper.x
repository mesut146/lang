import parser/ast
import parser/bridge
import parser/utils
import parser/own_visitor
import parser/own_model
import parser/ownership
import parser/compiler
import parser/resolver
import parser/compiler_helper
import parser/method_resolver
import parser/debug_helper
import parser/printer
import parser/derive
import std/map
import std/hashmap
import std/stack

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
        if let Rhs::EXPR(e)=(self){
            f.print("Rhs::EXPR{");
            f.print(e);
            f.print("}");
        }
        else if let Rhs::VAR(v*)=(self){
            //f.print("Rhs::VAR{");
            f.print(v);
            //f.print("}");
        }
        else if let Rhs::FIELD(scp*,name*)=(self){
            f.print("Rhs::FIELD{");
            f.print(scp);
            f.print(", ");
            f.print(name);
            f.print("}");
        }
    }
}
impl Clone for Rhs{
    func clone(self): Rhs{
        if let Rhs::EXPR(e)=(self){
            return Rhs::EXPR{e};
        }
        if let Rhs::VAR(v*)=(self){
            return Rhs::VAR{v.clone()};
        }
        if let Rhs::FIELD(scp*, name*)=(self){
            return Rhs::FIELD{scp: scp.clone(), name: name.clone()};
        }
        panic("{:?}", self);
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