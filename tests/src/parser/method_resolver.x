import parser/resolver
import parser/ast
import std/map

struct Signature{
    mc: Option<Call*>;
    m: Option<Method*>;
    args: List<Type>;
    scope: Option<RType>;
    ret: Type;
}

func is_static(mc: Call*): bool{
    return mc.scope.get().get() is Expr::Type;
}

impl Signature{
    func new(mc: Call*, r: Resolver*): Signature{
        let res = Signature{mc: Option::new(mc),
                            m: Option<Method*>::None,
                            args: List<Type>::new(),
                            scope: Option<RType>::None,
                            ret: Type::new("void")};
        let is_trait = false;                            
        if(mc.scope.is_some()){
            let scp = r.visit(mc.scope.get().get());
            //we need this to handle cases like Option::new(...)
            if (scp.targetDecl.is_some() && !scp.targetDecl.get().unit.path.eq(r.unit.path)) {
                r.addUsed(scp.targetDecl.unwrap());
            }
            if (scp.type.is_pointer()) {
                let inner = scp.type.unwrap();
                res.scope = Option::new(r.visit(&inner));
            } else {
                res.scope = Option::new(scp);
            }
            if (!is_static(mc)) {
                res.args.add(makeSelf(&res.scope.get().type));
            }
        }
        for(let i = 0;i < mc.args.len();++i){
            let arg = mc.args.get_ptr(i);
            let type = r.visit(arg).type;
            if(i == 0 && mc.scope.is_some() && is_struct(&type)){
                type = type.toPtr();
            }
            res.args.add(type);
        }
        return res;
    }
    func print(self): String{
        let s = String::new();
        if(self.mc.is_some()){
            if(self.mc.unwrap().scope.is_some()){
                s.append(self.scope.get().type.print());
                s.append("::");
            }
            s.append(self.mc.unwrap().name);
        }else{
            /*let p = self.m.unwrap().parent;
            if(p.is_some()){
                if(p){

                }
                s.append("::");
            }*/
            s.append(self.m.unwrap().name);
        }
        s.append("(");
        for(let i = 0;i < self.args.len();++i){
            if(i > 0){
                s.append(", ");
            }
            let arg = self.args.get_ptr(i);
            s.append(arg.print());
        }
        s.append(")");
        return s;
    }
}

struct MethodResolver{
    r: Resolver*;
}

impl MethodResolver{
    func new(r: Resolver*): MethodResolver{
        return MethodResolver{r: r};
    }

    func handle(self, sig: Signature*): RType{
        panic("handle %s", sig.print().cstr());
    }
}