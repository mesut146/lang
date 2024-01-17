import parser/resolver
import parser/ast
import parser/printer
import parser/utils
import parser/copier
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
            if (scp.targetDecl.is_some() && !scp.targetDecl.unwrap().unit.path.eq(&r.unit.path)) {
                r.addUsed(scp.targetDecl.unwrap());
            }
            if (scp.type.is_pointer()) {
                let inner = scp.type.unwrap_ptr();
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
        let map = Map<String, Type>::new();
        return Signature::new(m, &map);
    }
    func new(m: Method*, map: Map<String, Type>*): Signature{
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
            //if m is generic, replace <T> with real type
            let mapped = replace_type(&prm.type, map);
            res.args.add(replace_self(&mapped, m));
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
            let p = &self.m.unwrap().parent;
            if(p is Parent::Impl){
                s.append(p.as_impl().type.print());
                s.append("::");
            }
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
                let type_str = type.print();
                if(imp.info.type.print().eq(&type_str)){
                    list.add(imp);
                }
            }
        }
        return list;
    }

    func collect_static(self, sig: Signature*, list: List<Signature>*){
      let name=&sig.name;
      for (let i=0;i<self.r.unit.items.len();++i) {
        let item=self.r.unit.items.get_ptr(i);
        if let Item::Method(m*)=(item){
            if (m.name.eq(name)) {
                list.add(Signature::new(m));
            }
        } else if let Item::Extern(arr*)=(item){
            for (let j=0;j<arr.len();++j) {
                let m=arr.get_ptr(j);
                if (m.name.eq(name)) {
                    list.add(Signature::new(m));
                }
            }
        }
      }
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
                if(m.name.eq(&sig.name)){
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
            let msg = Fmt::format("no such method {}", sig.print().str());
            self.r.err(msg.str(), &e);
        }
        //test candidates and get errors
        let real = List<Signature*>::new();
        let errors = List<Pair<Signature*,String>>::new();
        let exact = Option<Signature*>::None;
        for(let i = 0;i < list.size();++i){
            let sig2 = list.get_ptr(i);
            let cmp_res = self.is_same(sig, sig2);
            if let SigResult::Err(err) = (cmp_res){
                errors.add(Pair::new(sig2, err.clone()));
            }else{
                if(cmp_res is SigResult::Exact){
                    exact = Option::new(sig2);
                }
                real.add(sig2);
            }
        }
        if(real.empty()){
            let e = Expr::Call{*mc};
            let msg = Fmt::format("method {} not found from candidates", mc.print().str());
            for(let i=0;i < errors.len();++i){
                let err = errors.get_ptr(i);
                msg.append("\n");
                msg.append(err.a.print());
                msg.append(" ");
                msg.append(err.b);
            }
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
            if (!target.path.eq(&self.r.unit.path)) {
                self.r.used_methods.add(target);
            }
            let res = self.r.visit(&sig2.ret);
            res.method = Option::new(target);
            return res;
        }
        let typeMap = Map<String, Option<Type>>::new();
        let type_params = get_type_params(target);

        //mark all as non inferred
        for (let i = 0;i < type_params.size();++i) {
            let ta = type_params.get_ptr(i);
            typeMap.add(*ta.name(), Option<Type>::None);
        }
        if (mc.scope.is_some()) {
            //todo trait
            let scope = &sig.scope.get().type;
            let scope_args = scope.get_args();
            for (let i = 0; i < scope_args.size(); ++i) {
                typeMap.add(*type_params.get_ptr(i).name(), Option::new(scope_args.get(i)));
            }
            if (!mc.tp.empty()) {
                panic("todo");
            }
        } else {
            if (!mc.tp.empty()) {
                //place specified type args in order
                for (let i = 0; i < mc.tp.size(); ++i) {
                    typeMap.add(*type_params.get_ptr(i).name(), Option::new(self.r.getType(mc.tp.get_ptr(i))));
                }
            }
        }
        //infer from args
        for (let i = 0; i < sig.args.size(); ++i) {
            let arg_type = sig.args.get_ptr(i);
            let target_type = sig2.args.get_ptr(i);
            MethodResolver::infer(arg_type, target_type, &typeMap);
        }
        let tmap = Map<String, Type>::new();
        for (let i = 0;i < typeMap.size();++i) {
            let pair = typeMap.get_idx(i).unwrap();
            if (pair.b.is_none()) {
                let msg = Fmt::format("can't infer type parameter: {}", pair.a.str());
                let e = Expr::Call{*mc};
                self.r.err(msg.str(), &e);
            }
            tmap.add(pair.a, *pair.b.get());
        }
        let target2 = self.generateMethod(&tmap, target, sig);
        target = target2;
        let res = self.r.visit(&target.type);
        res.method = Option::new(target);
        return res;
    }

    func is_same(self, sig: Signature*, sig2: Signature*): SigResult{
        let mc = sig.mc.unwrap();
        let m = sig2.m.unwrap();
        if(!mc.name.eq(&m.name)){
            return SigResult::Err{"not possible".str()};
        }
        if(!m.type_args.empty()){
            let mc_targs = &mc.tp;
            if (!mc_targs.empty() && mc_targs.size() != m.type_args.size()) {
                return SigResult::Err{"type arg size mismatched".str()};
            }
            if (!m.is_generic) {
                //check if args are compatible with generic type params
                for (let i = 0; i < mc_targs.size(); ++i) {
                    let ta1 = mc_targs.get_ptr(i).print();
                    let ta2 = m.type_args.get_ptr(i).print();
                    if (!ta1.eq(&ta2)) {
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
                    let scp = sig.args.get_ptr(0).unwrap_ptr();
                    if (!scp.name().eq(ty.name())) {
                        return SigResult::Err{Fmt::format("not same impl {} vs {}", scp.print().str(), ty.print().str())};
                    }
                } else if (!scope.name().eq(ty.name())) {
                    return SigResult::Err{Fmt::format("not same impl {} vs {}", scope.print().str(), ty.print().str())};
                }
                if (imp.type_params.empty() && !ty.get_args().empty()) {
                    //check they belong same impl
                    let scope_args = scope.get_args();
                    for (let i = 0; i < scope_args.size(); ++i) {
                        let tp_str = ty.get_args().get(i).print();
                        if (!scope_args.get_ptr(i).print().eq(&tp_str)){
                            return SigResult::Err{"not same impl".str()};
                        }
                    }
                }
            }
        }
        //check if args are compatible with non generic params
        return self.check_args(sig, sig2);
    }

    func check_args(self, sig: Signature*, sig2: Signature*): SigResult{
        if (sig2.m.unwrap().self.is_some() && !sig.mc.unwrap().scope.is_some()) {
            return SigResult::Err{"member method called without scope".str()};
        }
        if (sig.args.size() != sig2.args.size()) return SigResult::Err{"arg size mismatched".str()};
        let typeParams = get_type_params(sig2.m.unwrap());
        let all_exact = true;
        for (let i = 0; i < sig.args.size(); ++i) {
            let t1 = sig.args.get_ptr(i);
            let t2 = sig2.args.get_ptr(i);
            //todo if base method, skip self
            let t2_str = t2.print();
            if (!t1.print().eq(&t2_str)) {
                all_exact = false;
            }
            if (MethodResolver::is_compatible(RType::new(*t1), t2, &typeParams).is_some()) {
                return SigResult::Err{Fmt::format("arg type {} is not compatible with param {}", t1.print().str(), t2.print().str())};
            }
        }
        if(all_exact){
            return SigResult::Exact;
        }
        return SigResult::Compatible;
    }

    func is_compatible(arg0: RType, target: Type*, typeParams: List<Type>*): Option<String>{
        let arg = &arg0.type;
        if (isGeneric(target, typeParams)) return Option<String>::None;
        if (arg.print().eq(target.print().str())) return Option<String>::None;
        if (!arg.is_simple()) {
            let target_str = target.print();
            if (arg.print().eq(&target_str)) {
                return Option<String>::None;
            }
            if (kind(arg) != kind(target)) {
                return Option::new("internal error in is_compatible".str());
            }
            if (hasGeneric(target, typeParams)) {
                let trg_elem = target.elem();
                return MethodResolver::is_compatible(RType::new(*arg.elem()), trg_elem, typeParams);
            }
            //return arg.print() + " is not compatible with " + target.print();
            return Option::new("".str());
        }
        if (!arg.is_prim()) {
            return Option::new("".str());
        }
        if (!target.is_prim()) return Option::new("target is not prim".str());
        if (arg.print().eq("bool") || target.print().eq("bool")) return Option::new("target is not bool".str());
        if (arg0.value.is_some()) {
            //autocast literal
            let v = arg0.value.get();
            if (v.get(0) == '-') {
                if (isUnsigned(target)) return Option::new(Fmt::format("{} is signed but {} is unsigned", v.str(), target.print().str()));
                //check range
            } else {
                if (max_for(target) >= i64::parse(v)) {
                    return Option<String>::None;
                } else {
                    return Option::new(Fmt::format("{} can't fit into {}" ,v.str(), target.print().str()));
                }
            }
        }
        if (isUnsigned(target) && isSigned(arg)) {
            return Option::new("arg is signed but target is unsigned".str());
        }
        // auto cast to larger size
        if (prim_size(arg.name().str()).unwrap() <= prim_size(target.name().str()).unwrap()){
            return Option<String>::None;
        }
        else {
            return Option::new("arg can't fit into target".str());
        }
        panic("MethodResolver::is_compatible");
    }

    func is_compatible(arg0: RType, target: Type*): Option<String>{
        let arr = List<Type>::new();
        return MethodResolver::is_compatible(arg0, target, &arr);
    }

    func infer(arg: Type*, prm: Type*, typeMap: Map<String, Option<Type>>*) {
        if (prm.is_pointer()) {
            if (!arg.is_pointer()) return;
            infer(arg.scope(), prm.scope(), typeMap);
            return;
        }//todo
        let ta1 = arg.get_args();
        let ta2 = prm.get_args();
        if (ta2.empty()) {
            let nm = prm.name();
            if (typeMap.has(nm)) {//is_tp
                let it = typeMap.get_p(prm.name()).unwrap();
                if (it.is_none()) {//not set yet
                    typeMap.add(*prm.name(), Option::new(*arg));
                    print("inferred %s as %s\n", prm.print().cstr(), arg.print().cstr());
                    for(let i=0;i<typeMap.size();++i){
                        let p=typeMap.get_idx(i).unwrap();
                        print("map %s -> %s\n", p.a.cstr(), Fmt::str(&p.b).cstr());
                    }
                } else {//already set
                    let m = MethodResolver::is_compatible(RType::new(*arg), it.get());
                    if (m.is_some()) {
                        print("%s", m.get().cstr());
                        panic("type infer failed: %s vs %s", it.get().print().cstr(), arg.print().cstr());
                    }
                }
            }
        } else {
            if (ta1.size() != ta2.size()) {
                let msg = Fmt::format("type arg size mismatch, {} = {}", arg.print().str(), prm.print().str());
                panic("%s", msg.cstr());
            }
            if (!arg.name().eq(prm.name())) panic("cant infer");
            for (let i = 0; i < ta1.size(); ++i) {
                let ta = ta1.get_ptr(i);
                let tp = ta2.get_ptr(i);
                infer(ta, tp, typeMap);
            }
        }
    }

    func generateMethod(self, map: Map<String, Type>*, m: Method*, sig: Signature*): Method*{
        for (let i=0;i<self.r.generated_methods.size();++i) {
            let gm = self.r.generated_methods.get_ptr(i);
            let sig2 = Signature::new(gm);
            let res = self.is_same(sig, &sig2);
            if(!(res is SigResult::Err)){
                return gm;
            }
        }
        let copier = AstCopier::new(map);
        let res2 = copier.visit(m);
        self.r.generated_methods.add(res2);
        let res = self.r.generated_methods.get_ptr(self.r.generated_methods.len() - 1);
        if(!(m.parent is Parent::Impl)){
            return res;
        }
        let imp: ImplInfo* = get_impl(m);
        let st = *sig.scope.get().type.as_simple();
        if(sig.scope.get().trait.is_some()){
            st = *sig.args.get(0).unwrap_ptr().as_simple();
        }
        //put full type, Box::new(...) -> Box<...>::new()
        let imp_args = imp.type.get_args();
        if (sig.mc.unwrap().is_static && !imp_args.empty()) {
            st.args.clear();
            for (let i = 0;i < imp_args.size();++i) {
                let ta = imp_args.get_ptr(i);
                let ta_str = ta.print();
                let resolved = map.get_ptr(&ta_str).unwrap();
                st.args.add(*resolved);
            }
        }
        res.parent = Parent::Impl{ImplInfo::new(st.into())};
        return res;
    }

    func get_impl(m: Method*): ImplInfo*{
        if let Parent::Impl(info*) = (m.parent){
            return info;
        }
        panic("get_impl");
    }
}

func kind(type: Type*): i32{
    if(type is Type::Pointer) return 0;
    if(type is Type::Array) return 1;
    if(type is Type::Slice) return 2;
    panic("");
}

func get_type_params(m: Method*): List<Type>{
    let res = List<Type>::new();
    if (!m.is_generic) {
        return res;
    }
    if let Parent::Impl(info*) = (m.parent){
        res = info.type_params;
    }
    res.add(&m.type_args);
    return res;
}