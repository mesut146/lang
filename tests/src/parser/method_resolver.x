import parser/resolver
import parser/ast
import parser/printer
import std/map

struct Signature{
    mc: Option<Call*>;
    m: Option<Method*>;
    name: String;
    args: List<Type>;
    scope: Option<RType>;
    ret: Type;
    r: Option<Resolver*>;
}

enum SigResult{
    Err(s: String),
    Exact,
    Compatible
  }

func is_static(mc: Call*): bool{
    return mc.scope.get().get() is Expr::Type;
}

impl Signature{
    func new(mc: Call*, r: Resolver*): Signature{
        let res = Signature{mc: Option::new(mc),
                            m: Option<Method*>::None,
                            name: mc.name,
                            args: List<Type>::new(),
                            scope: Option<RType>::None,
                            ret: Type::new("void"),
                            r: Option::new(r)};
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
    /*func find_parent(m: Method*): Impl*{
        if(){

        }
    }*/
    func replace_self(type: Type*, m: Method*): Type{
        if(!type.print().eq("Self")){
            return *type;
        }
        if let Parent::Impl(info*) = (m.parent){
            return info.type;
        }
        panic("replace_self");
    }
    func make_inferred(sig: Signature*, type: Type*): Map<String, Type>{
        let type_plain = type.erase();
        let decl_opt = sig.r.unwrap().visit(&type_plain).targetDecl;
        let map = Map<String, Type>::new();
        if(decl_opt.is_none()){
            return map;
        }
        let decl = decl_opt.unwrap();
        if (decl.is_generic && type.is_generic()) {
            let args = decl.type.get_args();
            let args2 = type.get_args();
            for (let i = 0;i < args.len();++i) {
                let tp = args.get_ptr(i);
                map.add(tp.print(), *args2.get_ptr(i));
            }
        }
        return map;
    }
    func new(m: Method*): Signature{
        let res = Signature{mc: Option<Call*>::new(),
            m: Option<Method*>::new(m),
            name: m.name,
            args: List<Type>::new(),
            scope: Option<RType>::None,
            ret: replace_self(&m.type, m),
            r: Option<Resolver*>::None};
            if let Parent::Impl(info*) = (m.parent){
                let scp = RType::new(info.type);
                res.scope = Option::new(scp);
            }
            if(m.self.is_some()){
                res.args.add(m.self.get().type);
            }
            for(let i = 0;i < m.params.len();++i){
                let prm = m.params.get_ptr(i);
                res.args.add(prm.type);
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

    func collect(self, sig: Signature*): List<Signature>{
        let list = List<Signature>::new();
        if(sig.mc.unwrap().scope.is_some()){
            self.collect_member(sig, &list);
        }else{
            self.collect_static(sig, &list);
            let imports = self.r.get_imports();
            for (let i = 0;i < imports.len();++i) {
                let is = imports.get_ptr(i);
                let resolver = self.r.ctx.get_resolver(is);
                resolver.init();
                let mr = MethodResolver::new(resolver);
                mr.collect_static(sig, &list);
            }            
        }
        return list;
    }
    
    func get_impl(self, type: Type*): List<Impl*>{
        let list = List<Impl*>::new();
        for(let i = 0;i < self.r.unit.items.len();++i){
            let item = self.r.unit.items.get_ptr(i);
            if let Item::Impl(imp*) = (item){
                if(imp.info.type.print().eq(type.print())){
                    list.add(imp);
                }
            }
        }
        return list;
    }

    func collect_static(self, sig: Signature*, list: List<Signature>*){

    }

    func collect_member(self, sig: Signature*, list: List<Signature>*){
        let scope_type = sig.scope.get().type;
        let type_plain = scope_type;
        let imp_list = self.get_impl(&scope_type);
        for(let i = 0;i < imp_list.len();++i){
            let imp = imp_list.get(i);
            //print("impl found\n%s", Fmt::str(imp).cstr());
            for(let j = 0;j < imp.methods.len();++j){
                let m = imp.methods.get_ptr(j);
                if(m.name.eq(sig.name)){
                    list.add(Signature::new(m));
                }
            }
        }
    }

    func handle(self, sig: Signature*): RType{
        let mc = sig.mc.unwrap();
        let list = self.collect(sig);
        if(list.empty()){
            let e = Expr::Call{*sig.mc.unwrap()};
            self.r.err("no such method", &e);
        }
        //test candidates and get errors
        let real = List<Signature*>::new();
        let errors = List<Pair<Method*,String>>::new();
        let exact = Option<Signature*>::None;
        for(let i = 0;i < list.size();++i){
            let sig2 = list.get_ptr(i);
            let cmp_res = self.is_same(sig, sig2);
            if let SigResult::Err(err) = (cmp_res){
                errors.add(Pair::new(sig2.m.unwrap(), err.clone()));
            }else{
                if(cmp_res is SigResult::Exact){
                    exact = Option::new(sig2);
                }
                real.add(sig2);
            }
        }
        if(real.empty()){
            let e = Expr::Call{*mc};
            let msg = Fmt::format("method {} not found from candidates\n", mc.print().str());
            self.r.err(msg.str(), &e);
        }
        if (real.size() > 1 && exact.is_none()) {
            let e = Expr::Call{*mc};
            //let msg = format("method {} has {} candidates\n", mc.print().str(), real.size());
            let msg = Fmt::format("method {} has {} candidates\n", mc.print().str(), real.size().str().str());
            self.r.err(msg.str(), &e);
        }
        let sig2 = real.get(0);
        if(exact.is_some()){
            sig2 = exact.unwrap();
        }
        let target = sig2.m.unwrap();
        if (!target.is_generic) {
            if (!target.path.eq(self.r.unit.path)) {
                self.r.used_methods.add(target);
            }
            let res = self.r.visit(&sig2.ret);
            res.method = Option::new(target);
            return res;
        }    
        print("%s\n", target.print().cstr()); 
        panic("handle %s", sig.print().cstr());
    }

    func is_same(self, sig: Signature*, sig2: Signature*): SigResult{
        let mc = sig.mc.unwrap();
        let m = sig2.m.unwrap();
        assert mc.name.eq(m.name);
        if(!m.type_args.empty()){
            let mc_targs = get_type_args(mc);
            if (!mc_targs.empty() && mc_targs.size() != m.type_args.size()) {
                return SigResult::Err{"type arg size mismatched".str()};
            }
            if (!m.is_generic) {
                //check if args are compatible with generic type params
                for (let i = 0; i < mc_targs.size(); ++i) {
                    let ta1 = mc_targs.get_ptr(i).print();
                    let ta2 = m.type_args.get_ptr(i).print();
                    if (!ta1.eq(ta2)) {
                        let err = Fmt::format("type arg {} not compatible with {}", ta1.str(), ta2.str());
                        return SigResult::Err{err};
                    }
                }
            }
        }
        if let Parent::Impl(imp*) = (m.parent) {
            if(mc.scope.is_some()){
                let ty = &imp.type;
                let scope = sig.scope.get().type;
                if (sig.scope.get().trait.is_some()) {
                    let scp = sig.args.get_ptr(0).unwrap();
                    if (!scp.name.eq(ty.name())) {
                        return Fmt::format("not same impl {} vs {}", scp.print(), ty.print());
                    }
                } else if (!scope.name().eq(ty.name())) {
                    return Fmt::format("not same impl {} vs {}", scope.print().str(), ty.print().str());
                }
                if (imp.type_params.empty() && !ty.type_args.empty()) {
                    //check they belong same impl
                    let scope_args = scope.get_args();
                    for (let i = 0; i < scope_args.size(); ++i) {
                        if (!scope_args.get_ptr(i).print().eq(ty.type_args.get_ptr(i).print())){
                            return SigResult::Err{"not same impl".str()};
                        }
                    }
                }
            }
        }
        //check if args are compatible with non generic params
        return check_args(sig, sig2);
    }
}


func get_type_args(mc: Call*): List<Type>{
    panic("get_type_args");
}
