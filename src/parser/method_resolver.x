import parser/resolver
import parser/ast
import parser/printer
import parser/utils
import parser/copier
import parser/ownership
import std/map
import std/libc
import std/stack
import std/result

struct Signature{
    mc: Option<Call*>;
    m: Option<Method*>;
    name: String;
    args: List<Type>;
    scope: Option<RType>;
    r: Option<Resolver*>;
    desc: Desc;
}

#derive(Debug)
enum SigResult{
    Err(s: String),
    Exact,
    Compatible
}

impl SigResult{
    func get_err(self): str{
        if let SigResult::Err(s*)=(self){
            return s.str();
        }
        panic("SigResult::get_err");
    }
}

struct MethodResolver{
    r: Resolver*;
}

impl Signature{
    func new(name: String): Signature{
        return Signature{mc: Option<Call*>::new(),
                    m: Option<Method*>::new(),
                    name: name,
                    args: List<Type>::new(),
                    scope: Option<RType>::new(),
                    r: Option<Resolver*>::new(),
                    desc: Desc::new()
        };
    }
    func new(mc: Call*, r: Resolver*): Signature{
        let res = Signature{mc: Option::new(mc),
                    m: Option<Method*>::new(),
                    name: mc.name.clone(),
                    args: List<Type>::new(),
                    scope: Option<RType>::new(),
                    r: Option::new(r),
                    desc: Desc::new()
        };
        let is_trait = false;                            
        if(mc.scope.is_some()){
            let str = mc.print();
            //print("{}\n", str);
            let scp: RType = r.visit(mc.scope.get());
            let real_scope = Option::new(scp.clone());
            is_trait = scp.is_trait();
            //we need this to handle cases like Option::new(...)
            if (scp.is_decl()) {
                let trg: Decl* = r.get_decl(&scp).unwrap();
                if(!trg.is_generic && !trg.path.eq(&r.unit.path)){
                    r.add_used_decl(trg);
                }
            }
            res.scope.drop();
            if (scp.type.is_pointer()) {
                let inner = scp.type.get_ptr();
                res.scope = Option::new(r.visit_type(inner));
                scp.drop();
            } else {
                res.scope = Option::new(scp);
            }
            if (!mc.is_static) {
                res.args.add(real_scope.get().type.clone());
            }
            real_scope.drop();
            str.drop();
        }
        for(let i = 0;i < mc.args.len();++i){
            let arg = mc.args.get_ptr(i);
            let argt: RType = r.visit(arg);
            let type = argt.type.clone();
            argt.drop();
            res.args.add(type);
        }
        return res;
    }

    func make_inferred(sig: Signature*, type: Type*): Map<String, Type>{
        let map = Map<String, Type>::new();
        if(!type.is_simple()) return map;
        let type_plain: Type = type.erase();
        let decl_rt = sig.r.unwrap().visit_type(&type_plain);
        let decl_opt = sig.r.unwrap().get_decl(&decl_rt);
        type_plain.drop();
        decl_rt.drop();
        
        if(decl_opt.is_none()){
            return map;
        }
        let decl = decl_opt.unwrap();
        if (decl.is_generic && type.is_generic()) {
            let args = decl.type.get_args();
            let args2 = type.get_args();
            for (let i = 0;i < args.len();++i) {
                let tp = args.get_ptr(i);
                map.add(tp.print(), args2.get_ptr(i).clone());
            }
        }
        return map;
    }
    func new(m: Method*, desc: Desc, r: Resolver*, origin: Resolver*): Signature{
        let map = Map<String, Type>::new();
        let res = Signature::new(m, &map, desc, r, origin);
        map.drop();
        return res;
    }
    func replace_self(typ: Type*, m: Method*): Type{
        if(!typ.eq("Self")){
            return typ.clone();
        }
        if let Parent::Impl(info*)=(&m.parent){
            return info.type.clone();
        }
        panic("replace_self not impl method");
    }
    func new(m: Method*, map: Map<String, Type>*, desc: Desc, r: Resolver*, origin: Resolver*): Signature{
        let res = Signature{mc: Option<Call*>::new(),
            m: Option<Method*>::new(m),
            name: m.name.clone(),
            args: List<Type>::new(),
            scope: Option<RType>::new(),
            r: Option<Resolver*>::new(r),
            desc: desc
        };
        if let Parent::Impl(info*) = (&m.parent){
            let scp = RType::new(info.type.clone());
            res.scope = Option::new(scp);
        }
        if(m.self.is_some()){
            res.args.add(m.self.get().type.clone());
        }
        let copier = AstCopier::new(map);
        for(let i = 0;i < m.params.len();++i){
            let prm = m.params.get_ptr(i);
            //if m is generic, replace <T> with real type
            let mapped = copier.visit(&prm.type);
            let mapped2 = replace_self(&mapped, m);
            mapped.drop();
            mapped = mapped2;
            if(!hasGeneric(&mapped, m)){
                let mapped3 = origin.visit_type(&mapped).unwrap();
                mapped.drop();
                mapped = mapped3;
            }
            res.args.add(mapped);
        }
        return res;
    }
    func print(self): String{
        return Fmt::str(self);
    }
}

impl Debug for Signature{
    func debug(self, f: Fmt*){
        if(self.mc.is_some()){
            if(self.mc.unwrap().scope.is_some()){
                self.scope.get().type.debug(f);
                f.print("::");
            }
            f.print(&self.mc.unwrap().name);
        }else{
            let p = &self.m.unwrap().parent;
            if(p is Parent::Impl){
                p.as_impl().type.debug(f);
                f.print("::");
            }
            f.print(&self.m.unwrap().name);
        }
        f.print("(");
        for(let i = 0;i < self.args.len();++i){
            if(i > 0){
                f.print(", ");
            }
            let arg: Type* = self.args.get_ptr(i);
            arg.debug(f);
        }
        f.print(")");
    }
}

impl MethodResolver{
    func new(r: Resolver*): MethodResolver{
        return MethodResolver{r: r};
    }

    func collect(self, sig: Signature*): List<Signature>{
        let list = List<Signature>::new();
        if(sig.mc.unwrap().scope.is_some()){
            let scope_type = sig.scope.get().type.get_ptr();
            self.collect_member(sig, scope_type, &list, true, self.r);
        }else{
            //static sibling
            if(self.r.curMethod.is_some()){
                let cur = self.r.curMethod.unwrap();
                if let Parent::Impl(info*)=(&cur.parent){
                    self.collect_member(sig, &info.type, &list, false, self.r);
                }
            }            
            self.collect_static(sig.name.str(), &list, self.r);
            let arr = self.r.get_resolvers();
            for (let i = 0;i < arr.len();++i) {
                let resolver = *arr.get_ptr(i);
                resolver.init();
                let mr = MethodResolver::new(resolver);
                mr.collect_static(sig.name.str(), &list, self.r);
            }
            arr.drop();         
        }
        return list;
    }
    
    func print_erased(type: Type*): String{
      if(type.is_simple()){
        return type.name().clone();
      }
      return type.print();
    }
    
    func get_impl(self, type: Type*, tr: Option<Type*>): List<Pair<Impl*, i32>>{
        if(type.is_simple() && type.as_simple().scope.is_some()){
            self.r.err(type.line, "get_impl scoped type");
        }
        let list = List<Pair<Impl*, i32>>::new();
        let erased: String = print_erased(type);
        for(let i = 0;i < self.r.unit.items.len();++i){
            let item: Item* = self.r.unit.items.get_ptr(i);
            if(!(item is Item::Impl)) continue;
            let imp = item.as_impl();
            //print("imp {:?} {:?}\n", type, imp.info);
            if(tr.is_some()){
                if(imp.info.trait_name.is_none()){
                    continue;
                }
                if(!imp.info.trait_name.get().eq(*tr.get())){
                    continue;
                }
            }
            if(type.is_simple()){
                let imp_erased: String = print_erased(&imp.info.type);
                if(imp_erased.eq(&erased)){
                    list.add(Pair::new(imp, i));
                }
                imp_erased.drop();
            }else if(type.is_slice()){
                if(!imp.info.type.is_slice()){
                    continue;
                }
                let val = Option<String>::new();
                let cmp = is_compatible(type, &val, &imp.info.type, &imp.info.type_params);
                if(cmp.is_none()){
                    list.add(Pair::new(imp, i));
                }
                cmp.drop();
                val.drop();
            }else{
                panic("get_impl type not covered: {:?}", type);
            }
        }
        erased.drop();
        return list;
    }

    func get_impl(self, sig: Signature*, scope_type: Type*): List<Pair<Impl*, i32>>{
        if(sig.scope.is_some() && sig.scope.get().is_trait()){
            let actual: Type* = sig.args.get_ptr(0).get_ptr();
            return self.get_impl(actual, Option::new(&sig.scope.get().type));
        }else{
            return self.get_impl(scope_type, Option<Type*>::new());
        }
    }

    func collect_member(self, sig: Signature*, scope_type: Type*, list: List<Signature>*, use_imports: bool, origin: Resolver*){
        let imp_list: List<Pair<Impl*, i32>> = self.get_impl(sig, scope_type);
        //todo make this take real resolver

        let map = Signature::make_inferred(sig, scope_type);
        for(let i = 0;i < imp_list.len();++i){
            let pair: Pair<Impl*, i32>* = imp_list.get_ptr(i);
            let imp: Impl* = pair.a;
            for(let j = 0;j < imp.methods.len();++j){
                let m = imp.methods.get_ptr(j);       
                if(!m.name.eq(&sig.name)) continue;
                let desc = Desc{
                    kind: RtKind::MethodImpl{j},
                    path: m.path.clone(),
                    idx: pair.b
                };
                if(!scope_type.is_simple()){
                  list.add(Signature::new(m, desc, self.r, origin));
                  continue;
                }
                let scp_args = scope_type.get_args();
                if(scp_args.empty()){
                  list.add(Signature::new(m, &map, desc, self.r, origin));
                }else{
                  let typeMap = Map<String, Type>::new();
                  for(let k = 0;k < m.type_params.len();++k){
                    let ta = m.type_params.get_ptr(k);
                    typeMap.add(ta.name().clone(), scp_args.get_ptr(k).clone());
                  }
                  let sig2 = Signature::new(m, &map, desc, self.r, origin);
                  for (let k = 0;k < sig2.args.len();++k) {
                    let arg = sig2.args.get_ptr(k);
                    let ac = AstCopier::new(&typeMap);
                    let mapped = ac.visit(arg);
                    let tmp = sig2.args.set(k, mapped);
                    tmp.drop();
                  }
                  list.add(sig2);
                  typeMap.drop();
                }
            }
        }
        if (use_imports) {
          let arr: List<Resolver*> = self.r.get_resolvers();
          for (let i = 0;i < arr.len();++i) {
            let resolver = *arr.get_ptr(i);
            resolver.init();
            let mr = MethodResolver::new(resolver);
            mr.collect_member(sig, scope_type, list, false, origin);
            //self.collect_member(sig, scope_type, list, false);
          }
         arr.drop();
        }
        imp_list.drop();
        map.drop();
    }

    func collect_static(self, name: str, list: List<Signature>*, origin: Resolver*){
        for (let i = 0;i < self.r.unit.items.len();++i) {
            let item: Item* = self.r.unit.items.get_ptr(i);
            if let Item::Method(m*) = (item){
                if (m.name.eq(name)) {
                    let desc = Desc{kind: RtKind::Method,
                                    path: m.path.clone(),
                                    idx: i
                    };
                    list.add(Signature::new(m, desc, self.r, origin));
                }
            }
            else if let Item::Extern(arr*) = (item){
                for (let j = 0;j < arr.len();++j) {
                    let m = arr.get_ptr(j);
                    if (m.name.eq(name)) {
                        let desc = Desc{kind: RtKind::MethodExtern{j},
                            path: m.path.clone(),
                            idx: i
                        };
                        list.add(Signature::new(m, desc, self.r, origin));
                    }
                }
            }
        }
    }    

    func handle(self, expr: Expr*, sig: Signature*): RType{
        let mc = sig.mc.unwrap();
        let list = self.collect(sig);
        if(list.empty()){
            let msg = format("no such method {:?}", sig);
            self.r.err(expr, msg.str());
            panic("unreachable");
        }
        //test candidates and get errors
        let real = List<Signature*>::new();
        let errors = List<Pair<Signature*, String>>::new();
        let exact = Option<Signature*>::new();
        for(let i = 0;i < list.size();++i){
            let sig2 = list.get_ptr(i);
            let cmp_res: SigResult = self.is_same(sig, sig2);
            if let SigResult::Err(err) = (cmp_res){
                errors.add(Pair::new(sig2, err));
                //std::no_drop(cmp_res);
            }else{
                if(cmp_res is SigResult::Exact){
                    exact = Option::new(sig2);
                }
                real.add(sig2);
                cmp_res.drop();
            }
        }
        if(real.empty()){
            let f = Fmt::new(format("method {:?} not found from candidates\n", mc));
            for(let i = 0;i < errors.len();++i){
                let err: Pair<Signature*, String>* = errors.get_ptr(i);
                f.print(err.a);
                f.print(" ");
                f.print(&err.b);
                f.print("\n");
            }
            list.drop();
            real.drop();
            errors.drop();
            self.r.err(expr, f.unwrap());
            panic("unreachable");
        }
        if (real.size() > 1 && exact.is_none()) {
            let msg = format("method {:?} has {} candidates\n", mc, real.size());
            for(let i = 0;i < real.len();++i){
                let err: Signature* = *real.get_ptr(i);
                msg.append("\n  ");
                msg.append(err.print());
                msg.append(" ");
                msg.append(&err.m.unwrap_ptr().path);
            }
            list.drop();
            real.drop();
            errors.drop();
            self.r.err(expr, msg);
            panic("unreachable");
        }
        let sig2 = *real.get_ptr(0);
        if(exact.is_some()){
            sig2 = exact.unwrap();
        }
        let target: Method* = sig2.m.unwrap();
        if (!target.is_generic) {
            if (!target.path.eq(&self.r.unit.path)) {
                self.r.addUsed(target);
            }
            let res = self.r.visit_type(&target.type);
            res.method_desc = Option::new(sig2.desc.clone());
            list.drop();
            real.drop();
            errors.drop();
            return res;
        }
        let typeMap = Map<String, Type>::new();
        let type_params = get_type_params(target);
        //place user given type args
        if (mc.scope.is_some()) {
            //todo trait
            //is static & have type args
            let scope = &sig.scope.get().type;
            if(scope.is_simple()){
                let scope_args = scope.get_args();
                if let Expr::Type(scp*)=(mc.scope.get()){
                  scope = scp;
                  scope_args = scp.get_args();
                }
                for (let i = 0; i < scope_args.size(); ++i) {
                    typeMap.add(type_params.get_ptr(i).name().clone(), scope_args.get_ptr(i).clone());
                }
                if (!mc.type_args.empty()) {
                    //panic("todo");
                    //place specified type args in order
                    for (let i = 0; i < mc.type_args.size(); ++i) {
                        typeMap.add(type_params.get_ptr(i).name().clone(), self.r.getType(mc.type_args.get_ptr(i)));
                    }
                }
            }
        } else {
            if (!mc.type_args.empty()) {
                //place specified type args in order
                for (let i = 0; i < mc.type_args.size(); ++i) {
                    typeMap.add(type_params.get_ptr(i).name().clone(), self.r.getType(mc.type_args.get_ptr(i)));
                }
            }
        }
        //infer from args
        for (let k = 0; k < sig.args.size(); ++k) {
            let arg_type = sig.args.get_ptr(k);
            let target_type = sig2.args.get_ptr(k);
            //case for self coerced to ptr
            if(k == 0 && !mc.is_static && target.self.is_some() && target_type.is_pointer() && !arg_type.is_pointer()){
                let arg2 = arg_type.clone().toPtr();
                let err = MethodResolver::infer(&arg2, target_type, &typeMap, &type_params);
                if(err.is_err()){
                    self.r.err(expr, err.unwrap_err());
                }
                arg2.drop();
            }else{
                let err = MethodResolver::infer(arg_type, target_type, &typeMap, &type_params);
                if(err.is_err()){
                    self.r.err(expr, err.unwrap_err());
                }
            }
        }
        for (let i = 0;i < type_params.len();++i) {
            let tp = type_params.get_ptr(i);
            if (!typeMap.contains(tp.name())) {
                let msg = format("{:?}\ncan't infer type parameter: {:?}", sig, tp);
                type_params.drop();
                list.drop();
                real.drop();
                errors.drop();
                self.r.err(expr, msg);
                panic("unreachable");
            }
        }
        if(sig.scope.is_some()){
            let ac = AstCopier::new(&typeMap);
            let full_scope = ac.visit(&sig.scope.get().type);
            let scp_rt = sig.scope.get();
            //print("{} -> {} map={}\n", scp_rt.type, full_scope, typeMap);
            scp_rt.type = full_scope;
        }
        let gen_pair: Pair<Method*, Desc> = self.generateMethod(&typeMap, target, sig);
        typeMap.drop();
        let res = self.r.visit_type(&gen_pair.a.type);
        res.method_desc = Option::new(gen_pair.b);
        type_params.drop();
        list.drop();
        real.drop();
        errors.drop();
        return res;
    }

    func infer(arg: Type*, prm: Type*, inferred: Map<String, Type>*, type_params: List<Type>*): Result<i32, String>{
        if(type_params.contains(prm)){
            if(!inferred.contains(prm.name())){
                inferred.add(prm.name().clone(), arg.clone());
            }
            return Result<i32, String>::ok(0);
        }
        if (arg.is_pointer()) {
            if (!prm.is_pointer()){
                return Result<i32, String>::err("prm is not ptr".owned());
            }
            return infer(arg.elem(), prm.elem(), inferred, type_params);
        }
        if (arg.is_slice()) {
            if (!prm.is_slice()){
                return Result<i32, String>::err("prm is not slice".owned());
            }
            return infer(arg.elem(), prm.elem(), inferred, type_params);
        }
        if (arg.is_array()) {
            if (!prm.is_array()) return Result<i32, String>::err("prm is not array".owned());
            return infer(arg.elem(), prm.elem(), inferred, type_params);
        }
        if (arg.is_fpointer()) {
            if (!prm.is_fpointer()) return Result<i32, String>::err("prm is not func-ptr".owned());
            let ft1 = arg.get_ft();
            let ft2 = prm.get_ft();
            if(ft1.params.len() != ft2.params.len()){
                return Result<i32, String>::err("arg size not match".owned());
            }
            infer(&ft1.return_type, &ft2.return_type, inferred, type_params);
            for(let i = 0;i < ft1.params.len();++i){
                let a1 = ft1.params.get_ptr(i);
                let a2 = ft2.params.get_ptr(i);
                infer(a1, a2, inferred, type_params);
            }
            return Result<i32, String>::ok(0);
        }
        if (arg.is_lambda()) {
            if (!prm.is_fpointer()) panic("prm is not fptr");
            let ft1 = arg.get_lambda();
            let ft2 = prm.get_ft();
            if(ft1.params.len() != ft2.params.len()){
                panic("arg size not match");
            }
            if(ft1.return_type.is_none()){
                panic("lambda ret not resolved");
            }
            if(!ft1.captured.empty()){
                panic("lambda has captured");
            }
            infer(ft1.return_type.get(), &ft2.return_type, inferred, type_params);
            for(let i = 0;i < ft1.params.len();++i){
                let a1 = ft1.params.get_ptr(i);
                let a2 = ft2.params.get_ptr(i);
                infer(a1, a2, inferred, type_params);
            }
            return Result<i32, String>::ok(0);
        }
        if(!prm.is_simple()){
            panic("prm is not simple {:?} -> {:?}", arg, prm);
        }
        if(!prm.get_args().empty()){
            //prm: A<T>
            let ta1 = arg.get_args();
            let ta2 = prm.get_args();
            if (ta1.size() != ta2.size()) {
                let msg = format("type arg size mismatch, {:?} = {:?}", arg, prm);
                panic("{}", msg);
            }
            if (!arg.name().eq(prm.name())) panic("cant infer");
            for (let i = 0; i < ta1.size(); ++i) {
                let ta = ta1.get_ptr(i);
                let tp = ta2.get_ptr(i);
                infer(ta, tp, inferred, type_params);
            }
        }
        return Result<i32, String>::ok(0);
    }

    func generateMethod(self, map: Map<String, Type>*, m: Method*, sig: Signature*): Pair<Method*, Desc>{
        let mc = sig.mc.unwrap();
        let arr_opt = self.r.generated_methods.get(&m.name);
        if(arr_opt.is_some()){
            let i = 0;
            for gm in arr_opt.unwrap(){
                let sig2 = Signature::new(gm.get(), Desc::new(), self.r, self.r);
                let sig_res: SigResult = self.is_same(sig, &sig2);
                let is_err = sig_res is SigResult::Err;
                sig2.drop();
                sig_res.drop();
                if(!is_err){
                    let desc = Desc{
                        kind: RtKind::MethodGen{m.name.clone()},
                        path: self.r.unit.path.clone(),
                        idx: i
                    };
                    return Pair::new(gm.get(), desc);
                }
                ++i;
            }
        }
        let copier = AstCopier::new(map, &self.r.unit);
        let res2: Method = copier.visit(m);
        res2.is_generic = false;
        //print("add gen {} {}\n", printMethod(&res2), mc);
        if(arr_opt.is_none()){
            self.r.generated_methods.add(m.name.clone(), List<Box<Method>>::new());
            arr_opt = self.r.generated_methods.get(&m.name);
        }
        let desc = Desc{
            kind: RtKind::MethodGen{m.name.clone()},
            path: self.r.unit.path.clone(),
            idx: arr_opt.unwrap().len() as i32
        };
        self.r.generated_methods_todo.add(desc.clone());
        let res: Method* = arr_opt.unwrap().add(Box::new(res2)).get();
        if(!(m.parent is Parent::Impl)){
            return Pair::new(res, desc);
        }
        let imp: ImplInfo* = m.parent.as_impl();
        if(sig.scope.get().type.is_slice()){
            let info2 = res.parent.as_impl();
            info2.type_params.clear();
            return Pair::new(res, desc);
        }
        let st: Simple = sig.scope.get().type.clone().unwrap_simple();
        if(sig.scope.get().is_trait()){
            st.drop();
            st = sig.args.get_ptr(0).get_ptr().as_simple().clone();
        }
        //put full type, Box::new(...) -> Box<...>::new()
        let imp_args = imp.type.get_args();
        if (mc.is_static && !imp_args.empty()) {
            st.args.clear();
            for (let i = 0;i < imp_args.size();++i) {
                let ta = imp_args.get_ptr(i);
                let ta_str = ta.print();
                let resolved = map.get_ptr(&ta_str).unwrap();
                ta_str.drop();
                st.args.add(resolved.clone());
            }
        }
        res.parent.drop();
        let info = ImplInfo::new(st.into(res.line));
        //todo args of trait
        info.trait_name = imp.trait_name.clone();
        res.parent = Parent::Impl{info};
        return Pair::new(res, desc);
    }

    func is_same(self, scope_rt:  RType*, info: ImplInfo*, sig: Signature*): SigResult{
        let type1 = &scope_rt.type;
        let type2 = &info.type;
        if(type1.eq(type2)){
            return SigResult::Exact;
        }
        if(type1.is_slice()){
            if(!type2.is_slice()){
                return SigResult::Err{format("not same impl {:?} vs {:?}", type1, type2)};
            }
            if(info.type_params.empty()){
                return SigResult::Err{format("not same impl {:?} vs {:?}", type1, type2)};
            }
            let cmp = is_compatible(type1, type2, &info.type_params);
            if(cmp.is_some()){
                cmp.drop();
                return SigResult::Err{format("not same impl {:?} vs {:?}", type1, type2)};
            }
            cmp.drop();
            return SigResult::Exact;
            //panic("todo {} vs {}, mc={} cmp={}", type1, type2, sig.mc.unwrap(), &cmp);
        }
        if(!type1.is_simple() || !type2.is_simple()){
            return SigResult::Err{format("not same kind {:?} vs {:?}", type1, type2)};
        }
        if (scope_rt.is_trait()) {
            let real_scope = sig.args.get_ptr(0).get_ptr();
            if(info.trait_name.is_some()){
                if(!info.trait_name.get().name().eq(type1.name().str())){
                    return SigResult::Err{"not same trait".str()};
                }
                return SigResult::Exact;
            }
            else if (!real_scope.name().eq(type2.name())) {
                return SigResult::Err{format("not same impl {:?} vs {:?}", real_scope, type2)};
            }
        }
        if(info.type_params.empty()){
            return SigResult::Err{format("not same impl {:?} vs {:?}", type1, type2)};
        }
        if (!type1.name().eq(type2.name().str())) {
            return SigResult::Err{format("not same impl {:?} vs {:?}", type1, type2)};
            //return self.check_args(sig, sig2);
        }
        return SigResult::Exact;
    }

    func is_same(self, sig: Signature*, sig2: Signature*): SigResult{
        let mc = sig.mc.unwrap();
        let m = sig2.m.unwrap();
        if(!mc.name.eq(&m.name)){
            return SigResult::Err{"not possible".str()};
        }
        if(!m.type_params.empty()){
            let mc_targs = &mc.type_args;
            if (!mc_targs.empty() && mc_targs.size() != m.type_params.size()) {
                return SigResult::Err{"type arg size mismatched".str()};
            }
            if (!m.is_generic) {
                //check if args are compatible with generic type params
                for (let i = 0; i < mc_targs.size(); ++i) {
                    let ta1 = mc_targs.get_ptr(i);
                    let ta2 = m.type_params.get_ptr(i);
                    if (!ta1.eq(ta2)) {
                        let err = format("type arg {:?} not compatible with {:?}", ta1, ta2);
                        return SigResult::Err{err};
                    }
                }
            }
        }
        if(!(m.parent is Parent::Impl)){
            return self.check_args(sig, sig2);
        }
        if(mc.scope.is_none()){//static sibling
            return self.check_args(sig, sig2);
        }
        let imp: ImplInfo* = m.parent.as_impl();
        let ty = &imp.type;
        let scope: Type* = &sig.scope.get().type;
        let tmp = self.is_same(sig.scope.get(), imp, sig);
        if(tmp is SigResult::Err){
            return tmp;
        }
        tmp.drop();
        return self.check_args(sig, sig2);
        
    }

    func check_args(self, sig: Signature*, sig2: Signature*): SigResult{
        let mc = sig.mc.unwrap();
        let method = *sig2.m.get();
        if (method.self.is_some() && !mc.scope.is_some()) {
            return SigResult::Err{"member method called without scope".str()};
        }
        if (sig.args.len() != sig2.args.len()){
            if(!method.is_vararg || method.is_vararg && sig.args.len() < sig2.args.len() ){
                return SigResult::Err{format("arg size mismatched {} vs {}", sig.args.len(), sig2.args.len())};
            }
        }
        let typeParams = get_type_params(method);
        let all_exact = true;
      
        for (let i = 0; i < sig2.args.len(); ++i) {
            let t1: Type = sig.args.get_ptr(i).clone();
            let t1p: Type* = sig.args.get_ptr(i);
            let t2: Type* = sig2.args.get_ptr(i);
            if(i == 0 && method.self.is_some()){
                if (t2.is_pointer()) {
                    if (!t1.is_pointer()) {
                        //coerce to ptr
                        t1 = t1.toPtr();
                    }
                } else {
                    if (t1.is_pointer()) {
                        typeParams.drop();
                        t1.drop();
                        return SigResult::Err{format("can't convert borrowed self to *self, {:?} vs {:?}", t1p, t2)};
                    }
                }
            }
            let t1_str = t1.print();
            let t2_str = t2.print();
            if (!t1_str.eq(&t2_str)) {
                all_exact = false;
            }
            let cmp: Option<String> = MethodResolver::is_compatible(&t1, t2, &typeParams);
            if (cmp.is_some()) {
                let arg = String::new();
                arg.drop();
                if(method.self.is_some()){
                    if(mc.is_static){
                        arg = mc.args.get_ptr(i).print();
                    }else{
                        arg = mc.scope.get().print();
                    }
                }else{
                    if(!mc.is_static && mc.scope.is_some()){
                        arg = mc.scope.get().print();
                    }else{
                        arg = mc.args.get_ptr(i).print();
                    }
                }
                let res = SigResult::Err{format("arg '{:?}' is not compatible with param '{}' vs '{}'\n{}", arg, t1_str.str(), t2_str.str(), cmp.get())};
                arg.drop();
                t1_str.drop();
                t2_str.drop();
                typeParams.drop();
                cmp.drop();
                t1.drop();
                return res;
            }
            t1_str.drop();
            t2_str.drop();
            cmp.drop();
            t1.drop();
        }
        typeParams.drop();
        if(all_exact){
            return SigResult::Exact;
        }
        return SigResult::Compatible;
    }

    func is_compatible(arg: Type*, arg_val: Option<String>*, target: Type*): Option<String>{
        let typeParams = List<Type>::new();
        let res = is_compatible(arg, arg_val, target, &typeParams);
        typeParams.drop();
        return res;
    }

    func is_compatible(arg: Type*, arg_val: Option<String>*, target: Type*, typeParams: List<Type>*): Option<String>{
        let target_str = target.print();
        let arg_str = arg.print();
        let res = is_compatible(arg, &arg_str, arg_val, target, &target_str, typeParams);
        target_str.drop();
        arg_str.drop();
        return res;
    }

    func is_compatible(arg: Type*, arg_str: String*, arg_val: Option<String>*, target: Type*, target_str: String*, typeParams: List<Type>*): Option<String>{
        if (typeParams.contains(target)) return Option<String>::new();
        if (arg_str.eq(target_str.str())) return Option<String>::new();
        if(arg.is_pointer()){
            if(target.is_pointer()){
                let trg_elem = target.elem();
                return MethodResolver::is_compatible(arg.elem(), trg_elem, typeParams);
            }
            return Option::new("target is not pointer".str());
        }
        if(target.is_pointer()){
            return Option::new("arg is not pointer".str());
        }
        if(arg.is_fpointer()){
            if(!target.is_fpointer()){
                return Option::new("target is not fpointer".str());
            }
            let ft1 = arg.get_ft();
            let ft2 = target.get_ft();
            let cmp1 = MethodResolver::is_compatible(&ft1.return_type, &ft2.return_type, typeParams);
            if(cmp1.is_some()){
                return cmp1;
            }
            if(ft1.params.len() != ft2.params.len()){
                return Option::new("arg count mismatch".str());
            }
            for(let i = 0;i < ft1.params.len();++i){
                let cmp2 = MethodResolver::is_compatible(ft1.params.get_ptr(i), ft2.params.get_ptr(i), typeParams);
                if(cmp2.is_some()){
                    return cmp2;
                }
            }
            return Option<String>::new();
        }
        if(target.is_fpointer()){
            if(arg.is_lambda()){
                let lm = arg.get_lambda();
                let ft = target.get_ft();
                if(!lm.captured.empty()){
                    return Option::new("has captured".str());
                }
                if(lm.return_type.is_some()){
                    let cmp = is_compatible(lm.return_type.get(), &ft.return_type, typeParams);
                    if(cmp.is_some()){
                        return Option::new(format("ret mismatch {}", cmp.get()));
                    }
                }else{
                    return Option::new("lambda has no ret".str());
                }
                if(ft.params.len() != lm.params.len()){
                    return Option::new("arg count mismatch".str());
                }
                for(let i = 0;i < ft.params.len();++i){
                    let cmp2 = MethodResolver::is_compatible(lm.params.get_ptr(i), ft.params.get_ptr(i), typeParams);
                    if(cmp2.is_some()){
                        return cmp2;
                    }
                }
                return Option<String>::new();
            }
            return Option::new("arg is not fpointer".str());
        }
        if (!arg.is_simple()) {
            if(target.is_simple()){
                return Option::new("diff kind".str());
            }
            if (arg_str.eq(target_str)) {
                return Option<String>::new();
            }
            let lhs_kind = TypeKind::new(arg);
            let rhs_kind = TypeKind::new(target);
            if (!(lhs_kind is rhs_kind)) {
                return Option::new("internal error in is_compatible".str());
            }
            if (hasGeneric(target, typeParams)) {
                let trg_elem = target.elem();
                return MethodResolver::is_compatible(arg.elem(), trg_elem, typeParams);
            }
            return Option::new("unknown".str());
        }
        if(!target.is_simple()){
            return Option::new("diff kind".str());
        }
        //both simple
        if (!arg.is_prim()) {
            //arg struct
            if (target.is_prim()) return Option::new("target is prim".str());
            let targs = arg.get_args();
            let targs2 = target.get_args();
            if(!arg.name().eq(target.name())){
                return Option::new("not match".str());
            }
            if(targs.len() != targs2.len()){
                return Option::new(format("type args size dont match {} vs {}", targs.len(), targs2.len()));
            }
            if(!hasGeneric(target, typeParams)){
                //target is generated param, must match whole
                if (arg_str.eq(target_str)) {
                    return Option<String>::new();
                } else {
                    return Option::new("type args don't match".str());
                }
            }
            //A<i32> and A<i64> not compatible
            for (let i = 0; i < targs.len(); ++i) {
                let ta = targs.get_ptr(i);
                let tp = targs2.get_ptr(i);
                let cmp = is_compatible(ta, tp, typeParams);
                if (cmp.is_some()) {
                    return cmp;
                }
                /*if (cmp.cast) {
                    return CompareResult("cant cast subtype");
                }*/
                cmp.drop();
            }
            return Option<String>::new();
        }
        if (!target.is_prim()) return Option::new("target is not prim".str());
        if (arg_str.eq("bool") || target_str.eq("bool")) return Option::new("target is not bool".str());
        if (arg_val.is_some()) {
            //autocast literal
            let v: String* = arg_val.get();
            if (v.get(0) == '-') {
                if (isUnsigned(target)) {
                    return Option::new(format("{} is signed but {} is unsigned", v.str(), target_str.str()));
                }
                //check range
            } else {
                if (max_for(target) >= i64::parse(v.str())) {
                    return Option<String>::new();
                } else {
                    return Option::new(format("{} can't fit into {}", v.str(), target_str.str()));
                }
            }
        }
        if (isUnsigned(target) && isSigned(arg)) {
            return Option::new("arg is signed but target is unsigned".str());
        }
        // auto cast to larger size
        if (prim_size(arg.name().str()).unwrap() <= prim_size(target.name().str()).unwrap()){
            return Option<String>::new();
        }
        else {
            return Option::new(format("{:?} can't fit into {}", arg, target_str.str()));
        }
    }

    func is_compatible(arg: Type*, target: Type*): Option<String>{
        let arr = List<Type>::new();
        let arg_val = Option<String>::new();
        let res = MethodResolver::is_compatible(arg, &arg_val, target, &arr);
        arr.drop();
        arg_val.drop();
        return res;
    }
    func is_compatible(arg: Type*, target: Type*, arr: List<Type>*): Option<String>{
        let arg_val = Option<String>::new();
        let res = MethodResolver::is_compatible(arg, &arg_val, target, arr);
        arg_val.drop();
        return res;
    }

}

func get_type_params(m: Method*): List<Type>{
    let res = List<Type>::new();
    if (!m.is_generic) {
        return res;
    }
    if let Parent::Impl(info*) = (&m.parent){
        res.drop();
        res = info.type_params.clone();
    }
    res.add_list(m.type_params.clone());
    return res;
}

func hasGeneric(type: Type*, m: Method*): bool{
    let arr = get_type_params(m);
    let res = hasGeneric(type, &arr);
    arr.drop();
    return res;
}