import parser/resolver
import parser/ast
import parser/printer
import parser/utils
import parser/copier
import std/map
import std/libc

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

impl SigResult{
    func get_err(self): str{
        if let SigResult::Err(s*)=(self){
            return s.str();
        }
        panic("SigResult::get");
    }
}

struct MethodResolver{
    r: Resolver*;
}

func is_static(mc: Call*): bool{
    return mc.scope.get().get() is Expr::Type;
}

impl Signature{
    func new(mc: Call*, r: Resolver*): Signature{
        let res = Signature{mc: Option::new(mc),
                            m: Option<Method*>::None,
                            name: mc.name.clone(),
                            args: List<Type>::new(),
                            scope: Option<RType>::None,
                            ret: Type::new("void"),
                            r: Option::new(r)};
        let is_trait = false;                            
        if(mc.scope.is_some()){
            let scp: RType = r.visit(mc.scope.get().get());
            is_trait = scp.trait.is_some();
            //we need this to handle cases like Option::new(...)
            if (scp.targetDecl.is_some()) {
                let trg = scp.targetDecl.unwrap();
                let bd = trg as BaseDecl*;
                let p = &bd.path;
                if(!trg.is_generic && !trg.path.eq(&r.unit.path)){
                    r.addUsed(trg);
                }
            }
            Drop::drop(res.scope);
            if (scp.type.is_pointer()) {
                let inner = scp.type.unwrap_ptr();
                res.scope = Option::new(r.visit(inner));
                Drop::drop(scp);
            } else {
                res.scope = Option::new(scp);
            }
            if (!is_static(mc)) {
                res.args.add(makeSelf(&res.scope.get().type));
            }
        }
        for(let i = 0;i < mc.args.len();++i){
            let arg = mc.args.get_ptr(i);
            let argt: RType = r.visit(arg);
            let type = argt.type.clone();
            Drop::drop(argt);
            if(i == 0 && mc.scope.is_some() && is_trait && is_struct(&type)){
                type = type.toPtr();
            }
            res.args.add(type);
        }
        return res;
    }

    func make_inferred(sig: Signature*, type: Type*): Map<String, Type>{
        let map = Map<String, Type>::new();
        if(!type.is_simple()) return map;
        let type_plain: Type = type.erase();
        let decl_rt = sig.r.unwrap().visit(&type_plain);
        let decl_opt = decl_rt.targetDecl;
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
    func new(m: Method*): Signature{
        let map = Map<String, Type>::new();
        let res = Signature::new(m, &map);
        Drop::drop(map);
        return res;
    }
    func new(m: Method*, map: Map<String, Type>*): Signature{
        let res = Signature{mc: Option<Call*>::new(),
            m: Option<Method*>::new(m),
            name: m.name.clone(),
            args: List<Type>::new(),
            scope: Option<RType>::None,
            ret: replace_self(&m.type, m),
            r: Option<Resolver*>::None};
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
            let scope_type = sig.scope.get().type.unwrap_ptr();
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
            let imports = self.r.get_imports();
            for (let i = 0;i < imports.len();++i) {
                let is = imports.get_ptr(i);
                let resolver = self.r.ctx.get_resolver(is);
                resolver.init();
                let mr = MethodResolver::new(resolver);
                mr.collect_static(sig, &list);
            }
            Drop::drop(imports);          
        }
        return list;
    }
    
    func print_erased(type: Type*): String{
      if(type.is_simple()){
        return type.name().clone();
      }
      return type.print();
    }
    
    func get_impl(self, type: Type*): List<Impl*>{
        let list = List<Impl*>::new();
        let erased: String = print_erased(type);
        for(let i = 0;i < self.r.unit.items.len();++i){
            let item = self.r.unit.items.get_ptr(i);
            if let Item::Impl(imp*) = (item){
                let imp_erased: String = print_erased(&imp.info.type);
                if(imp_erased.eq(&erased)){
                  list.add(imp);
                }else if(imp.info.trait_name.is_some()){
                  let tr = imp.info.trait_name.get().name();
                  if(tr.eq(&erased)){
                    list.add(imp);
                  }
                }
                Drop::drop(imp_erased);
            }
        }
        Drop::drop(erased);
        return list;
    }

    func collect_static(self, sig: Signature*, list: List<Signature>*){
      let name = &sig.name;
      for (let i = 0;i < self.r.unit.items.len();++i) {
        let item = self.r.unit.items.get_ptr(i);
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

    func collect_member(self, sig: Signature*, scope_type: Type*, list: List<Signature>*, imports: bool){
        //let scope_type = sig.scope.get().type.unwrap_ptr();
        //let type_plain = scope_type;
        let imp_list: List<Impl*> = self.get_impl(scope_type);
        if(sig.scope.is_some() && sig.scope.get().trait.is_some()){
            let actual: Type* = sig.args.get_ptr(0).unwrap_ptr();
            let tmp = self.get_impl(actual);
            imp_list.add(&tmp);
            Drop::drop(tmp);
        }
        let map = Signature::make_inferred(sig, scope_type);
        for(let i = 0;i < imp_list.len();++i){
            let imp = *imp_list.get_ptr(i);
            for(let j = 0;j < imp.methods.len();++j){
                let m = imp.methods.get_ptr(j);       
                if(!m.name.eq(&sig.name)) continue;
                if(!scope_type.is_simple()){
                  list.add(Signature::new(m));
                  continue;
                }
                let scp_args = scope_type.get_args();
                if(scp_args.empty()){
                  list.add(Signature::new(m, &map));
                }else{
                  let typeMap = Map<String, Type>::new();
                  for(let k = 0;k < m.type_params.len();++k){
                    let ta = m.type_params.get_ptr(k);
                    typeMap.add(ta.name().clone(), scp_args.get_ptr(k).clone());
                  }
                  let sig2 = Signature::new(m, &map);
                  for (let k = 0;k < sig2.args.len();++k) {
                    let arg = sig2.args.get_ptr(k);
                    let ac = AstCopier::new(&typeMap);
                    let mapped = ac.visit(arg);
                    sig2.args.set(k, mapped);
                  }
                  Drop::drop(typeMap);
                  list.add(sig2);
                }
            }
        }
        if (imports) {
          let ims: List<ImportStmt> = self.r.get_imports();
          for (let i = 0;i < ims.len();++i) {
            let is = ims.get_ptr(i);
            let resolver = self.r.ctx.get_resolver(is);
            resolver.init();
            let mr = MethodResolver::new(resolver);
            mr.collect_member(sig, scope_type, list, false);
          }
          Drop::drop(ims);
        }
        Drop::drop(imp_list);
        Drop::drop(map);
    }

    func handle(self, expr: Expr*, sig: Signature*): RType{
        let mc = sig.mc.unwrap();
        let list = self.collect(sig);
        if(list.empty()){
            let msg = format("no such method {}", sig);
            self.r.err(expr, msg.str());
            Drop::drop(msg);
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
            let msg = Fmt::format("method {} not found from candidates", mc.print().str());
            for(let i=0;i < errors.len();++i){
                let err = errors.get_ptr(i);
                msg.append("\n");
                msg.append(err.a.print().str());
                msg.append(" ");
                msg.append(err.b.str());
            }
            Drop::drop(list);
            Drop::drop(real);
            Drop::drop(errors);
            self.r.err(expr, msg.str());
        }
        if (real.size() > 1 && exact.is_none()) {
            let msg = Fmt::format("method {} has {} candidates\n", mc.print().str(), i64::print(real.size()).str());
            for(let i=0;i < real.len();++i){
                let err = *real.get_ptr(i);
                msg.append("\n");
                msg.append(err.print().str());
            }
            Drop::drop(list);
            Drop::drop(real);
            Drop::drop(errors);
            self.r.err(expr, msg.str());
        }
        let sig2 = real.get(0);
        if(exact.is_some()){
            sig2 = exact.unwrap();
        }
        let target = sig2.m.unwrap();
        if (!target.is_generic) {
            if (!target.path.eq(&self.r.unit.path)) {
                self.r.addUsed(target);
            }
            //let res = self.r.visit(&sig2.ret);
            let res = self.r.visit(&target.type);
            res.method = Option::new(target);
            Drop::drop(list);
            Drop::drop(real);
            Drop::drop(errors);
            return res;
        }
        let typeMap = Map<String, Option<Type>>::new();
        let type_params = get_type_params(target);

        //mark all as non inferred
        for (let i = 0;i < type_params.size();++i) {
            let ta = type_params.get_ptr(i);
            typeMap.add(ta.name().clone(), Option<Type>::None);
        }
        if (mc.scope.is_some()) {
            //todo trait
            //is static & have type args
            let scope = &sig.scope.get().type;
            let scope_args = scope.get_args();
            if let Expr::Type(scp*)=(mc.scope.get().get()){
              scope = scp;
              scope_args=scp.get_args();
            }
            for (let i = 0; i < scope_args.size(); ++i) {
                typeMap.add(type_params.get_ptr(i).name().clone(), Option::new(scope_args.get_ptr(i).clone()));
            }
            if (!mc.type_args.empty()) {
                panic("todo");
            }
        } else {
            if (!mc.type_args.empty()) {
                //place specified type args in order
                for (let i = 0; i < mc.type_args.size(); ++i) {
                    typeMap.add(type_params.get_ptr(i).name().clone(), Option::new(self.r.getType(mc.type_args.get_ptr(i))));
                }
            }
        }
        Drop::drop(type_params);
        Drop::drop(list);
        Drop::drop(real);
        Drop::drop(errors);
        //infer from args
        for (let i = 0; i < sig.args.size(); ++i) {
            let arg_type = sig.args.get_ptr(i);
            let target_type = sig2.args.get_ptr(i);
            MethodResolver::infer(arg_type, target_type, &typeMap);
        }
        let tmap = Map<String, Type>::new();
        for (let i = 0;i < typeMap.len();++i) {
            let pair = typeMap.get_idx(i).unwrap();
            if (pair.b.is_none()) {
                let msg = Fmt::format("can't infer type parameter: {}", pair.a.str());
                self.r.err(expr, msg.str());
            }
            tmap.add(pair.a.clone(), pair.b.get().clone());
        }
        let target2 = self.generateMethod(&tmap, target, sig);
        Drop::drop(tmap);
        Drop::drop(typeMap);
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
                        let err = Fmt::format("type arg {} not compatible with {}", ta1.str(), ta2.str());
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
        let scope = &sig.scope.get().type;
        let scope_str = scope.print();
        let ty_str = ty.print();
        if(ty_str.eq(scope_str.str())){
            Drop::drop(ty_str);
            return self.check_args(sig, sig2);
        }

        if (sig.scope.get().trait.is_some()) {
            let real_scope = sig.args.get_ptr(0).unwrap_ptr();
            if(imp.trait_name.is_some()){
                if(!imp.trait_name.get().name().eq(scope.name().str())){
                    return SigResult::Err{"not same trait".str()};
                }
                return self.check_args(sig, sig2);
            }
            else if (!real_scope.name().eq(ty.name())) {
                let real_scope_str =  real_scope.print();
                return SigResult::Err{Fmt::format("not same impl {} vs {}", real_scope_str.str(), ty_str.str())};
            }
        } else if (!scope.name().eq(ty.name().str())) {
            return SigResult::Err{Fmt::format("not same impl {} vs {}", scope_str.str(), ty_str.str())};
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
            if(!sig.scope.get().targetDecl.unwrap().is_generic){
                let scope_args = scope.get_args();
                for (let i = 0; i < scope_args.size(); ++i) {
                    let tp_str = ty.get_args().get_ptr(i).print();
                    let scope_args_str = scope_args.get_ptr(i).print();
                    if (!scope_args_str.eq(&tp_str)){
                        return SigResult::Err{"not same impl".str()};
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
            let t1_str = t1.print();
            let t2_str = t2.print();
            if (!t1_str.eq(&t2_str)) {
                all_exact = false;
            }
            let cmp: Option<String> = MethodResolver::is_compatible(t1, t2, &typeParams);
            if (cmp.is_some()) {
                let res = SigResult::Err{Fmt::format("arg type {} is not compatible with param {}", t1_str.str(), t2_str.str())};
                Drop::drop(t1_str);
                Drop::drop(t2_str);
                Drop::drop(typeParams);
                Drop::drop(cmp);
                return res;
            }
            Drop::drop(t2_str);
            Drop::drop(t1_str);
            Drop::drop(cmp);
        }
        Drop::drop(typeParams);
        if(all_exact){
            return SigResult::Exact;
        }
        return SigResult::Compatible;
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
        if (isGeneric(target, typeParams)) return Option<String>::None;
        if (arg_str.eq(target_str.str())) return Option<String>::None;
        if(arg.is_pointer()){
            if(target.is_pointer()){
                let trg_elem = target.elem();
                return MethodResolver::is_compatible(arg.elem(), trg_elem, typeParams);
            }
            return Option::new("target is not pointer".str());
        }
        if (!arg.is_simple()) {
            if(target.is_simple()){
                return Option::new("".str());
            }
            if (arg_str.eq(target_str)) {
                return Option<String>::None;
            }
            if (kind(arg) != kind(target)) {
                return Option::new("internal error in is_compatible".str());
            }
            if (hasGeneric(target, typeParams)) {
                let trg_elem = target.elem();
                return MethodResolver::is_compatible(arg.elem(), trg_elem, typeParams);
            }
            //return arg_str + " is not compatible with " + target_str;
            return Option::new("".str());
        }
        if (!arg.is_prim()) {
            return Option::new("".str());
        }
        if (!target.is_prim()) return Option::new("target is not prim".str());
        if (arg_str.eq("bool") || target_str.eq("bool")) return Option::new("target is not bool".str());
        if (arg_val.is_some()) {
            //autocast literal
            let v: String* = arg_val.get();
            if (v.get(0) == '-') {
                if (isUnsigned(target)) {
                    return Option::new(Fmt::format("{} is signed but {} is unsigned", v.str(), target_str.str()));
                }
                //check range
            } else {
                if (max_for(target) >= i64::parse(v.str())) {
                    return Option<String>::None;
                } else {
                    return Option::new(Fmt::format("{} can't fit into {}" ,v.str(), target_str.str()));
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

    func infer(arg: Type*, prm: Type*, typeMap: Map<String, Option<Type>>*) {
        if (prm.is_pointer()) {
            if (!arg.is_pointer()) return;
            infer(arg.unwrap_ptr(), prm.unwrap_ptr(), typeMap);
            return;
        }
        else if(arg.is_pointer()) {
            if(typeMap.contains(prm.name())){
                typeMap.add(prm.name().clone(), Option::new(arg.clone()));
                return;
            }
            panic("cant infer ");
        }
        if(prm.is_slice()){
            if (!arg.is_slice()) return;
            infer(arg.elem(), prm.elem(), typeMap);
            return;
        }
        if(arg.is_slice()){
            if(typeMap.contains(prm.name())){
                typeMap.add(prm.name().clone(), Option::new(arg.clone()));
                return;
            }
            panic("cant infer ");
        }
        //todo
        if (prm.as_simple().args.empty()) {
            let nm: String* = prm.name();
            if (typeMap.contains(nm)) {//is_tp
                let opt = typeMap.get_ptr(nm);
                let it: Option<Type>* = opt.unwrap();
                if (it.is_none()) {//not set yet
                    typeMap.add(prm.name().clone(), Option::new(arg.clone()));
                    //print("inferred {} as {}\n", prm.print().cstr(), arg.print().cstr());
                    //for(let i=0;i<typeMap.size();++i){
                        //let p=typeMap.get_idx(i).unwrap();
                        //print("map {} -> {}\n", p.a.cstr(), Fmt::str(&p.b).cstr());
                    //}
                } else {//already set
                    let cmp: Option<String> = MethodResolver::is_compatible(arg, it.get());
                    if (cmp.is_some()) {
                        print("{}\n", cmp.get());
                        panic("type infer failed: {} vs {}\n", it.get().print(), arg.print());
                    }
                    Drop::drop(cmp);
                }
            }
        } else {
            let ta1 = arg.get_args();
            let ta2 = prm.get_args();
            if (ta1.size() != ta2.size()) {
                let arg_s = arg.print();
                let prm_s = prm.print();
                let msg = Fmt::format("type arg size mismatch, {} = {}", arg_s.str(), prm_s.str());
                Drop::drop(arg_s);
                Drop::drop(prm_s);
                panic("{}", msg);
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
        for (let i = 0;i < self.r.generated_methods.len();++i) {
            let gm = self.r.generated_methods.get_ptr(i);
            if(!m.name.eq(gm.name.str())) continue;
            let sig2 = Signature::new(gm);
            let sig_res: SigResult = self.is_same(sig, &sig2);
            Drop::drop(sig2);
            if(!(sig_res is SigResult::Err)){
                Drop::drop(sig_res);
                return gm;
            }else{
                Drop::drop(sig_res);
            }
        }
        let copier = AstCopier::new(map, &self.r.unit);
        let res2 = copier.visit(m);
        res2.is_generic = false;
        self.r.generated_methods.add(res2);
        let res: Method* = self.r.generated_methods.get_ptr(self.r.generated_methods.len() - 1);
        if(!(m.parent is Parent::Impl)){
            return res;
        }
        let imp: ImplInfo* = get_impl_info(m);
        let st: Simple = sig.scope.get().type.clone().unwrap_simple();
        if(sig.scope.get().trait.is_some()){
            Drop::drop(st);
            st = sig.args.get_ptr(0).unwrap_ptr().as_simple().clone();
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
        res.parent = Parent::Impl{ImplInfo::new(st.into())};
        return res;
    }

    func get_impl_info(m: Method*): ImplInfo*{
        if let Parent::Impl(info*) = (&m.parent){
            return info;
        }
        panic("get_impl_info");
    }
}

func kind(type: Type*): i32{
    if(type is Type::Pointer) return 0;
    if(type is Type::Array) return 1;
    if(type is Type::Slice) return 2;
    panic("{}\n", type);
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
    res.add(&m.type_params);
    return res;
}