import parser/resolver
import parser/ast
import parser/printer
import parser/utils
import parser/copier
import parser/ownership
import std/map
import std/libc

struct Signature{
    mc: Option<Call*>;
    m: Option<Method*>;
    name: String;
    args: List<Type>;
    scope: Option<RType>;
    r: Option<Resolver*>;
    desc: Desc;
}

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
        return Signature{mc: Option<Call*>::None,
                    m: Option<Method*>::None,
                    name: name,
                    args: List<Type>::new(),
                    scope: Option<RType>::None,
                    r: Option<Resolver*>::None,
                    desc: Desc::new()
        };
    }
    func new(mc: Call*, r: Resolver*): Signature{
        let res = Signature{mc: Option::new(mc),
                    m: Option<Method*>::None,
                    name: mc.name.clone(),
                    args: List<Type>::new(),
                    scope: Option<RType>::None,
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
            Drop::drop(res.scope);
            if (scp.type.is_pointer()) {
                let inner = scp.type.get_ptr();
                res.scope = Option::new(r.visit_type(inner));
                Drop::drop(scp);
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
            Drop::drop(argt);
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
        Drop::drop(type_plain);
        Drop::drop(decl_rt);
        
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
    func new(m: Method*, desc: Desc): Signature{
        let map = Map<String, Type>::new();
        let res = Signature::new(m, &map, desc);
        Drop::drop(map);
        return res;
    }
    func new(m: Method*, map: Map<String, Type>*, desc: Desc): Signature{
        let res = Signature{mc: Option<Call*>::new(),
            m: Option<Method*>::new(m),
            name: m.name.clone(),
            args: List<Type>::new(),
            scope: Option<RType>::None,
            r: Option<Resolver*>::None,
            desc: desc};
        if let Parent::Impl(info*) = (&m.parent){
            let scp = RType::new(info.type.clone());
            res.scope = Option::new(scp);
        }
        if(m.self.is_some()){
            res.args.add(m.self.get().type.clone());
        }
        for(let i = 0;i < m.params.len();++i){
            let prm = m.params.get_ptr(i);
            //if m is generic, replace <T> with real type
            let mapped = replace_type(&prm.type, map);
            res.args.add(replace_self(&mapped, m));
            Drop::drop(mapped);
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
            self.collect_member(sig, scope_type, &list, true);
        }else{
            //static sibling
            if(self.r.curMethod.is_some()){
                let cur = self.r.curMethod.unwrap();
                if let Parent::Impl(info*)=(&cur.parent){
                    self.collect_member(sig, &info.type, &list, false);
                }
            }            
            self.collect_static(sig, &list);
            let arr = self.r.get_resolvers();
            for (let i = 0;i < arr.len();++i) {
                let resolver = *arr.get_ptr(i);
                resolver.init();
                let mr = MethodResolver::new(resolver);
                mr.collect_static(sig, &list);
            }
            Drop::drop(arr);          
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
        let list = List<Pair<Impl*, i32>>::new();
        let erased: String = print_erased(type);
        for(let i = 0;i < self.r.unit.items.len();++i){
            let item: Item* = self.r.unit.items.get_ptr(i);
            if(!(item is Item::Impl)) continue;
            let imp = item.as_impl();
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
                Drop::drop(imp_erased);
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
                panic("get_impl type not covered: {}", type);
            }
        }
        Drop::drop(erased);
        return list;
    }

    func collect_static(self, sig: Signature*, list: List<Signature>*){
      let name = &sig.name;
      for (let i = 0;i < self.r.unit.items.len();++i) {
        let item: Item* = self.r.unit.items.get_ptr(i);
        if let Item::Method(m*) = (item){
            if (m.name.eq(name)) {
                let desc = Desc{kind: RtKind::Method,
                    path: m.path.clone(),
                    idx: i};
                list.add(Signature::new(m, desc));
            }
        } else if let Item::Extern(arr*) = (item){
            for (let j = 0;j < arr.len();++j) {
                let m = arr.get_ptr(j);
                if (m.name.eq(name)) {
                    let desc = Desc{kind: RtKind::MethodExtern{j},
                        path: m.path.clone(),
                        idx: i};
                    list.add(Signature::new(m, desc));
                }
            }
        }
      }
    }

    func collect_member(self, sig: Signature*, scope_type: Type*, list: List<Signature>*, use_imports: bool){
        //let scope_type = sig.scope.get().type.get_ptr();
        //let type_plain = scope_type;
        if(sig.mc.unwrap().print().eq("(&slice).iter()") && self.r.unit.path.str().ends_with("it.x")){
            let xx = 10;
        }
        let imp_list = List<Pair<Impl*, i32>>::new();
        Drop::drop(imp_list);
        if(sig.scope.is_some() && sig.scope.get().is_trait()){
            let actual: Type* = sig.args.get_ptr(0).get_ptr();
            imp_list = self.get_impl(actual, Option::new(&sig.scope.get().type));
        }else{
            imp_list = self.get_impl(scope_type, Option<Type*>::new());
        }
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
                  list.add(Signature::new(m, desc));
                  continue;
                }
                let scp_args = scope_type.get_args();
                if(scp_args.empty()){
                  list.add(Signature::new(m, &map, desc));
                }else{
                  let typeMap = Map<String, Type>::new();
                  for(let k = 0;k < m.type_params.len();++k){
                    let ta = m.type_params.get_ptr(k);
                    typeMap.add(ta.name().clone(), scp_args.get_ptr(k).clone());
                  }
                  let sig2 = Signature::new(m, &map, desc);
                  for (let k = 0;k < sig2.args.len();++k) {
                    let arg = sig2.args.get_ptr(k);
                    let ac = AstCopier::new(&typeMap);
                    let mapped = ac.visit(arg);
                    let tmp = sig2.args.set(k, mapped);
                    tmp.drop();
                  }
                  list.add(sig2);
                  Drop::drop(typeMap);
                }
            }
        }
        if (use_imports) {
          let arr: List<Resolver*> = self.r.get_resolvers();
          for (let i = 0;i < arr.len();++i) {
            let resolver = *arr.get_ptr(i);
            resolver.init();
            let mr = MethodResolver::new(resolver);
            mr.collect_member(sig, scope_type, list, false);
          }
          Drop::drop(arr);
        }
        Drop::drop(imp_list);
        Drop::drop(map);
    }

    func handle(self, expr: Expr*, sig: Signature*): RType{
        let mc = sig.mc.unwrap();
        dbg(expr.print(), "(&slice).iter()", 35);
        let list = self.collect(sig);
        if(list.empty()){
            let msg = format("no such method {}", sig);
            self.r.err(expr, msg.str());
            panic("unreachable");
        }
        //test candidates and get errors
        let real = List<Signature*>::new();
        let errors = List<Pair<Signature*, String>>::new();
        let exact = Option<Signature*>::None;
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
                Drop::drop(cmp_res);
            }
        }
        if(real.empty()){
            let f = Fmt::new(format("method {} not found from candidates\n", mc));
            for(let i = 0;i < errors.len();++i){
                let err: Pair<Signature*, String>* = errors.get_ptr(i);
                f.print(err.a);
                f.print(" ");
                f.print(&err.b);
                f.print("\n");
            }
            Drop::drop(list);
            Drop::drop(real);
            Drop::drop(errors);
            self.r.err(expr, f.unwrap());
            panic("unreachable");
        }
        if (real.size() > 1 && exact.is_none()) {
            let msg = format("method {} has {} candidates\n", mc, real.size());
            for(let i = 0;i < real.len();++i){
                let err: Signature* = *real.get_ptr(i);
                msg.append("\n");
                msg.append(err.print());
                msg.append(err.m.unwrap_ptr().path);
            }
            Drop::drop(list);
            Drop::drop(real);
            Drop::drop(errors);
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
            Drop::drop(list);
            Drop::drop(real);
            Drop::drop(errors);
            return res;
        }
        let typeMap = Map<String, Type>::new();
        let type_params = get_type_params(target);
        //place user given type args
        if (mc.scope.is_some()) {
            //todo trait
            //is static & have type args
            let scope = &sig.scope.get().type;
            let scope_args = scope.get_args();
            if let Expr::Type(scp*)=(mc.scope.get()){
              scope = scp;
              scope_args = scp.get_args();
            }
            for (let i = 0; i < scope_args.size(); ++i) {
                typeMap.add(type_params.get_ptr(i).name().clone(), scope_args.get_ptr(i).clone());
            }
            if (!mc.type_args.empty()) {
                panic("todo");
            }
        } else {
            if (!mc.type_args.empty()) {
                //place specified type args in order
                for (let i = 0; i < mc.type_args.size(); ++i) {
                    typeMap.add(type_params.get_ptr(i).name().clone(), self.r.getType(mc.type_args.get_ptr(i)));
                }
            }
        }
        dbg(mc.print(), "Debug::debug(self.value, f)", 10);
        //infer from args
        for (let k = 0; k < sig.args.size(); ++k) {
            let arg_type = sig.args.get_ptr(k);
            let target_type = sig2.args.get_ptr(k);
            //case for self coerced to ptr
            if(k == 0 && !mc.is_static && target.self.is_some() && target_type.is_pointer() && !arg_type.is_pointer()){
                let arg2 = arg_type.clone().toPtr();
                MethodResolver::infer(&arg2, target_type, &typeMap, &type_params);
                arg2.drop();
            }else{
                MethodResolver::infer(arg_type, target_type, &typeMap, &type_params);
            }
        }
        for (let i = 0;i < type_params.len();++i) {
            let tp = type_params.get_ptr(i);
            if (!typeMap.contains(tp.name())) {
                let msg = format("{}\ncan't infer type parameter: {}", sig, tp);
                dbg(true, 1);
                Drop::drop(type_params);
                Drop::drop(list);
                Drop::drop(real);
                Drop::drop(errors);
                self.r.err(expr, msg);
                panic("unreachable");
            }
        }
        let gen_pair: Pair<Method*, Desc> = self.generateMethod(&typeMap, target, sig);
        Drop::drop(typeMap);
        let res = self.r.visit_type(&gen_pair.a.type);
        res.method_desc = Option::new(gen_pair.b);
        Drop::drop(type_params);
        Drop::drop(list);
        Drop::drop(real);
        Drop::drop(errors);
        return res;
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
                    let ta1 = mc_targs.get_ptr(i).print();
                    let ta2 = m.type_params.get_ptr(i).print();
                    if (!ta1.eq(&ta2)) {
                        let err = format("type arg {} not compatible with {}", ta1, ta2);
                        Drop::drop(ta1);
                        Drop::drop(ta2);
                        return SigResult::Err{err};
                    }
                    Drop::drop(ta1);
                    Drop::drop(ta2);
                }
            }
        }
        if(!(m.parent is Parent::Impl)){
            return self.check_args(sig, sig2);
        }
        if(mc.scope.is_none()){//static sibling
            return self.check_args(sig, sig2);
        }
        let imp = m.parent.as_impl();
        let ty = &imp.type;
        let scope: Type* = &sig.scope.get().type;
        if(ty.eq(scope)){
            return self.check_args(sig, sig2);
        }

        if (sig.scope.get().is_trait()) {
            let real_scope = sig.args.get_ptr(0).get_ptr();
            if(imp.trait_name.is_some()){
                if(!imp.trait_name.get().name().eq(scope.name().str())){
                    return SigResult::Err{"not same trait".str()};
                }
                return self.check_args(sig, sig2);
            }
            else if (!real_scope.name().eq(ty.name())) {
                return SigResult::Err{format("not same impl {} vs {}", real_scope, ty)};
            }
        } else if (!scope.name().eq(ty.name().str())) {
            return SigResult::Err{format("not same impl {} vs {}", scope, ty)};
            //return self.check_args(sig, sig2);
        } else{
        }
        /*let cmp = is_compatible(RType::new(scope.clone()), &imp.type, &imp.type_params);
        if(cmp.is_some()){
            return SigResult::Err{Fmt::format("not same impl {} vs {}", scope.print().str(), imp.type.print().str())};
        }*/
        if (imp.type_params.empty() && ty.is_simple() && !ty.get_args().empty()) {
            //generated method impl
            //check they belong same impl
            let scp_rt = sig.scope.get();
            let scp_rt2 = Option<RType>::new();
            if(sig.scope.get().is_method()){
                let tmp = self.r.visit_type(&scp_rt.type);
                scp_rt2 = Option::new(tmp);
                scp_rt = scp_rt2.get();
            }
            else if(sig.scope.get().is_trait()){
                //??
            }else{
                let decl = self.r.get_decl(scp_rt).unwrap();
                if(!decl.is_generic){
                    let scope_args = scope.get_args();
                    for (let i = 0; i < scope_args.size(); ++i) {
                        let tp = ty.get_args().get_ptr(i);
                        let scope_arg = scope_args.get_ptr(i);
                        if (!scope_arg.eq(tp)){
                            scp_rt2.drop();
                            return SigResult::Err{"not same impl".str()};
                        }
                    }
                }
            }
            scp_rt2.drop();
        }
        //check if args are compatible with non generic params
        return self.check_args(sig, sig2);
    }

    func check_args(self, sig: Signature*, sig2: Signature*): SigResult{
        let mc = sig.mc.unwrap();
        let method = *sig2.m.get();
        if (method.self.is_some() && !mc.scope.is_some()) {
            return SigResult::Err{"member method called without scope".str()};
        }
        if (sig.args.len() != sig2.args.len()){
            return SigResult::Err{format("arg size mismatched {} vs {}", sig.args.len(), sig2.args.len())};
        }
        let typeParams = get_type_params(method);
        let all_exact = true;
        dbg(mc.print(), "Drop::drop(pair.b)", 66);
      
        for (let i = 0; i < sig.args.len(); ++i) {
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
                        return SigResult::Err{format("can't convert borrowed self to *self, {} vs {}", t1p, t2)};
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
                let res = SigResult::Err{format("arg is not compatible with param {}({}) vs {}\n{}\nagrs: {}", t1_str.str(), arg, t2_str.str(), cmp.get(), typeParams)};
                arg.drop();
                Drop::drop(t1_str);
                Drop::drop(t2_str);
                Drop::drop(typeParams);
                Drop::drop(cmp);
                t1.drop();
                return res;
            }
            Drop::drop(t1_str);
            Drop::drop(t2_str);
            Drop::drop(cmp);
            t1.drop();
        }
        Drop::drop(typeParams);
        if(all_exact){
            return SigResult::Exact;
        }
        return SigResult::Compatible;
    }

    func is_compatible(arg: Type*, arg_val: Option<String>*, target: Type*): Option<String>{
        let typeParams = List<Type>::new();
        let res = is_compatible(arg, arg_val, target, &typeParams);
        Drop::drop(typeParams);
        return res;
    }

    func is_compatible(arg: Type*, arg_val: Option<String>*, target: Type*, typeParams: List<Type>*): Option<String>{
        let target_str = target.print();
        let arg_str = arg.print();
        let res = is_compatible(arg, &arg_str, arg_val, target, &target_str, typeParams);
        Drop::drop(target_str);
        Drop::drop(arg_str);
        return res;
    }

    func is_compatible(arg: Type*, arg_str: String*, arg_val: Option<String>*, target: Type*, target_str: String*, typeParams: List<Type>*): Option<String>{
        if (isGeneric2(target, typeParams)) return Option<String>::None;
        if (arg_str.eq(target_str.str())) return Option<String>::None;
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
        if (!arg.is_simple()) {
            if(target.is_simple()){
                return Option::new("diff kind".str());
            }
            if (arg_str.eq(target_str)) {
                return Option<String>::None;
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
            //return arg_str + " is not compatible with " + target_str;
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
                    return Option<String>::None;
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
            return Option<String>::None;
        }
        else {
            return Option::new(format("{} can't fit into {}", arg, target_str.str()));
        }
    }

    func is_compatible(arg: Type*, target: Type*): Option<String>{
        let arr = List<Type>::new();
        let arg_val = Option<String>::new();
        let res = MethodResolver::is_compatible(arg, &arg_val, target, &arr);
        Drop::drop(arr);
        Drop::drop(arg_val);
        return res;
    }
    func is_compatible(arg: Type*, target: Type*, arr: List<Type>*): Option<String>{
        let arg_val = Option<String>::new();
        let res = MethodResolver::is_compatible(arg, &arg_val, target, arr);
        Drop::drop(arg_val);
        return res;
    }

    func infer(arg: Type*, prm: Type*, inferred: Map<String, Type>*, type_params: List<Type>*) {
        if(type_params.contains(prm)){
            if(!inferred.contains(prm.name())){
                inferred.add(prm.name().clone(), arg.clone());
            }
            return;
        }
        if (arg.is_pointer()) {
            if (!prm.is_pointer()) panic("prm is not ptr");
            infer(arg.elem(), prm.elem(), inferred, type_params);
            return;
        }
        if (arg.is_slice()) {
            if (!prm.is_slice()) panic("prm is not slice");
            infer(arg.elem(), prm.elem(), inferred, type_params);
            return;
        }
        if (arg.is_array()) {
            if (!prm.is_array()) panic("prm is not array");
            infer(arg.elem(), prm.elem(), inferred, type_params);
            return;
        }
        if(!prm.is_simple()){
            panic("prm is not simple {} -> {}", arg, prm);
        }
        if(!prm.get_args().empty()){
            //prm: A<T>
            let ta1 = arg.get_args();
            let ta2 = prm.get_args();
            if (ta1.size() != ta2.size()) {
                let arg_s = arg.print();
                let prm_s = prm.print();
                let msg = format("type arg size mismatch, {} = {}", arg_s.str(), prm_s.str());
                Drop::drop(arg_s);
                Drop::drop(prm_s);
                panic("{}", msg);
            }
            if (!arg.name().eq(prm.name())) panic("cant infer");
            for (let i = 0; i < ta1.size(); ++i) {
                let ta = ta1.get_ptr(i);
                let tp = ta2.get_ptr(i);
                infer(ta, tp, inferred, type_params);
            }
        }else {
            //prm: T
            /*let nm: String* = prm.name();
            if (type_params.contains(nm)) {
                let opt = typeMap.get_ptr(nm);
                let it: Option<Type>* = opt.unwrap();
                if (it.is_none()) {//not set yet
                    typeMap.add(prm.name().clone(), Option::new(arg.clone()));
                } else {//already set
                    let cmp: Option<String> = MethodResolver::is_compatible(arg, it.get());
                    if (cmp.is_some()) {
                        print("{}\n", cmp.get());
                        panic("type infer failed: {} vs {}\n", it.get().print(), arg.print());
                    }
                    Drop::drop(cmp);
                }
            }*/
        }
    }

    func generateMethod(self, map: Map<String, Type>*, m: Method*, sig: Signature*): Pair<Method*, Desc>{
        for (let i = 0;i < self.r.generated_methods.len();++i) {
            let gm = self.r.generated_methods.get_ptr(i).get();
            if(!m.name.eq(gm.name.str())) continue;
            let sig2 = Signature::new(gm, Desc::new());
            dbg(sig.mc.unwrap().print(), "one(3, 4)", 2);
            let sig_res: SigResult = self.is_same(sig, &sig2);
            let is_err = sig_res is SigResult::Err;
            Drop::drop(sig2);
            Drop::drop(sig_res);
            if(!is_err){
                let desc = Desc{
                    kind: RtKind::MethodGen,
                    path: self.r.unit.path.clone(),
                    idx: i
                };
                return Pair::new(gm, desc);
            }
        }
        let copier = AstCopier::new(map, &self.r.unit);
        let res2: Method = copier.visit(m);
        res2.is_generic = false;
        dbg(printMethod(&res2), "Option<RType>::drop(*self)", 10);
        //print("add gen {} {}\n", printMethod(&res2), sig.mc.get_ptr());
        let res: Method* = self.r.generated_methods.add(Box::new(res2)).get();
        let desc = Desc{
            kind: RtKind::MethodGen,
            path: self.r.unit.path.clone(),
            idx: self.r.generated_methods.len() as i32 - 1
        };
        if(!(m.parent is Parent::Impl)){
            return Pair::new(res, desc);
        }
        let imp: ImplInfo* = m.parent.as_impl();
        let st: Simple = sig.scope.get().type.clone().unwrap_simple();
        if(sig.scope.get().is_trait()){
            Drop::drop(st);
            st = sig.args.get_ptr(0).get_ptr().as_simple().clone();
        }
        //put full type, Box::new(...) -> Box<...>::new()
        let imp_args = imp.type.get_args();
        if (sig.mc.unwrap().is_static && !imp_args.empty()) {
            st.args.clear();
            for (let i = 0;i < imp_args.size();++i) {
                let ta = imp_args.get_ptr(i);
                let ta_str = ta.print();
                let resolved = map.get_ptr(&ta_str).unwrap();
                Drop::drop(ta_str);
                st.args.add(resolved.clone());
            }
        }
        Drop::drop(res.parent);
        let info = ImplInfo::new(st.into(res.line));
        //todo args of trait
        info.trait_name = imp.trait_name.clone();
        res.parent = Parent::Impl{info};
        return Pair::new(res, desc);
    }
}

func get_type_params(m: Method*): List<Type>{
    let res = List<Type>::new();
    if (!m.is_generic) {
        return res;
    }
    if let Parent::Impl(info*) = (&m.parent){
        Drop::drop(res);
        res = info.type_params.clone();
    }
    res.add_list(m.type_params.clone());
    return res;
}