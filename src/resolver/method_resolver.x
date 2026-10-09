import std/map
import std/hashmap
import std/libc
import std/stack
import std/result

import ast/copier
import ast/ast
import ast/printer
import ast/utils

import resolver/resolver
import parser/ownership

import resolver/method_sig

struct MethodResolver{
    r: Resolver*;
}


impl MethodResolver{
    func new(r: Resolver*): MethodResolver{
        return MethodResolver{r: r};
    }

    func collect(self, sig: Signature*): Result<List<Signature>, String>{
        let list = List<Signature>::new();
        if(sig.mc.unwrap().scope.is_some()){
            let scope_type = sig.scope.get().type.deref_ptr();
            let r = self.collect_member(sig, scope_type, &list, true, self.r);
            if(r.is_err()){
                return Result<List<Signature>, String>::err(r.unwrap_err());
            }
            //free functions inside modules: M::useA()
            self.collect_module_funcs(sig, scope_type, &list, self.r);
        }else{
            //static sibling
            if(self.r.curMethod.is_some()){
                let cur = self.r.curMethod.unwrap();
                if let Parent::Impl(info)=&cur.parent{
                    let r = self.collect_member(sig, &info.type, &list, false, self.r);
                    if(r.is_err()){
                        return Result<List<Signature>, String>::err(r.unwrap_err());
                    }
                }
            }            
            self.collect_static(sig.name.str(), &list, self.r);
            let arr = self.r.get_resolvers();
            for (let i = 0;i < arr.len();++i) {
                let resolver = *arr.get(i);
                resolver.init();
                let mr = MethodResolver::new(resolver);
                mr.collect_static(sig.name.str(), &list, self.r);
            }
        }
        return Result<List<Signature>, String>::ok(list);
    }
    
    func print_erased(type: Type*): String{
      if(type.is_simple()){
        return type.name().clone();
      }
      return type.print();
    }

    func get_impl(resolver: Resolver*, type: Type*, tr: Option<Type*>): Result<List<ImplHit>, String>{
        return MethodResolver::get_impl(resolver, &resolver.unit.items, type, tr);
    }
    
    func get_impl(resolver: Resolver*, items: List<Item>*, type: Type*, tr: Option<Type*>): Result<List<ImplHit>, String>{
      match type{
        Type::Slice(sl) => {},
        Type::Simple(sl) => {},
        _ => {
            return Result<List<ImplHit>, String>::err(format("get_impl type not covered: {:?}", type));
        }
      }
      //Scoped searches (M::A) combine impls nested inside the module
      //(recursion with stripped name, collected below) with impls spelled
      //with the scope at this level (root `impl M::A`, matched in the loop
      //below). Name filtering happens downstream in collect_member.
      let scoped = List<ImplHit>::new();
      if(type.is_simple()){
        let smp = type.as_simple();
        if(smp.scope.is_some()){
          //scope can be module: search inside it with stripped name...
          let tmp = resolver.visit_type0(smp.scope.get());
          if(tmp.is_ok()){
            let rt = tmp.unwrap();
            let md = resolver.get_module(&rt);
            if(md.is_none()){
              return Result<List<ImplHit>, String>::err(format("scope is not module {:?}", type));
            }
            let smp2 = smp.clone();
            smp2.scope = Ptr<Type>::new();
            let type2 = smp2.into(type.line);
            let rec = MethodResolver::get_impl(resolver, &md.unwrap().items, &type2, tr);
            if(rec.is_ok()){
              let found = rec.unwrap();
              for(let i = 0;i < found.len();++i){
                let fp = found.get(i);
                scoped.add(ImplHit{imp: fp.imp, idx: fp.idx, scope: Option::new(smp.scope.get().clone())});
              }
            }else{
              return rec;
            }
          }
          //...and also check current items for impls spelled with the
          //same scope (root-level `impl M::A`), which the recursion
          //above can never see. Falls through to the loop below.
        }
      }
      let list = scoped;
      let erased: String = print_erased(type);
      //todo generated impl too
      for(let i = 0;i < items.len();++i){
        let item: Item* = items.get(i);
        if(!(item is Item::Impl)) continue;
        let imp = item.as_impl();
        if(!trait_matches(imp, tr)){
            continue;
        }
        if(type.is_simple()){
            let smp = type.as_simple();
            if(smp.scope.is_some()){
                //scoped search (M::A): match impls spelled with the same
                //scope, e.g. root-level `impl M::A` (the module recursion
                //above only sees impls nested inside M).
                let full = type.print();
                let imp_full = imp.info.type.print();
                if(full.eq(&imp_full)){
                    list.add(ImplHit{imp: imp, idx: i, scope: Option<Type>::new()});
                }
                full.drop();
                imp_full.drop();
            }else{
                let imp_erased: String = print_erased(&imp.info.type);
                if(imp_erased.eq(&erased)){
                    list.add(ImplHit{imp: imp, idx: i, scope: Option<Type>::new()});
                }
                imp_erased.drop();
            }
        }else if(type.is_slice()){
            if(!imp.info.type.is_slice()){
                continue;
            }
            let val = Option<String>::new();
            let cmp = is_compatible(type, &val, &imp.info.type, &imp.info.type_params);
            if(cmp.is_none()){
                list.add(ImplHit{imp: imp, idx: i, scope: Option<Type>::new()});
            }
            cmp.drop();
            val.drop();
        }else{
            return Result<List<ImplHit>, String>::err(format("get_impl type not covered: {:?}", type));
        }
      }
      //sibling modules: impls spelled with the full search scope but
      //nested in a different module (impl M::A inside mod N). The loop
      //above only sees root items and the recursion only descends the
      //scope's own module. Exact full-print matches only, so unscoped
      //searches are unaffected.
      if(type.is_simple() && type.as_simple().scope.is_some()){
        let full = type.print();
        for(let k = 0;k < items.len();++k){
          let top = items.get(k);
          if let Item::Module(md) = top{
            scan_mod_items(&md.items, Type::new(md.name.clone()), &full, tr, &list);
          }
        }
      }
      return Result<List<ImplHit>, String>::ok(list);
    }

    func get_impl(self, sig: Signature*, scope_type: Type*): Result<List<ImplHit>, String>{
        if(sig.scope.is_some() && sig.scope.get().is_trait()){
            let actual: Type* = sig.args.get(0).deref_ptr();
            return get_impl(self.r, actual, Option::new(&sig.scope.get().type));
        }else{
            return get_impl(self.r, scope_type, Option<Type*>::new());
        }
    }

    func collect_module_funcs(self, sig: Signature*, scope_type: Type*, list: List<Signature>*, origin: Resolver*){
        //Free functions nested in modules (M::useA()). Purely syntactic
        //descent by scope segments: no type visits here, this runs
        //mid-collection where generic scopes may not resolve (and visits
        //have side effects like drop synthesis). Same-file modules only.
        //Only non-generic functions for now; idx is module-local
        //(see get_method), scope records where to find it.
        let segs = List<String>::new();
        let cur: Type* = scope_type;
        while(true){
            if(!cur.is_simple()){
                segs.drop();
                return;
            }
            let smp = cur.as_simple();
            segs.add(smp.name.clone());
            if(!smp.scope.is_some()){
                break;
            }
            cur = smp.scope.get();
        }
        //segs is inner-first; walk top-level items down from the outer end
        let items = &self.r.unit.items;
        let md: Module* = ptr::null<Module>();
        for(let i = segs.len() - 1;i >= 0;--i){
            let want = segs.get(i);
            let found: Module* = ptr::null<Module>();
            for(let j = 0;j < items.len();++j){
                let item = items.get(j);
                if let Item::Module(m) = item{
                    if(m.name.eq(want.str())){
                        found = m;
                        break;
                    }
                }
            }
            if(found as u64 == 0){
                segs.drop();
                return;
            }
            md = found;
            items = &md.items;
        }
        for(let i = 0;i < items.len();++i){
            let item = items.get(i);
            if let Item::Method(m) = item{
                if(!m.name.eq(&sig.name)) continue;
                if(m.is_generic) continue;
                let desc = Desc{
                    kind: RtKind::Method,
                    path: m.path.clone(),
                    idx: i,
                    scope: Option::new(scope_type.clone()),
                };
                list.add(Signature::new(m, desc, self.r, origin));
            }
        }
    }

    func collect_member(self, sig: Signature*, scope_type: Type*, list: List<Signature>*, use_imports: bool, origin: Resolver*): Result<i32, String>{
        let imp_list0 = self.get_impl(sig, scope_type);
        if(imp_list0.is_err()){
            return Result<i32, String>::err(imp_list0.unwrap_err());
        }
        let imp_list: List<ImplHit> = imp_list0.unwrap();
        //todo make this take real resolver

        let map = Signature::make_inferred(sig, scope_type);
        for(let i = 0;i < imp_list.len();++i){
            let hit: ImplHit* = imp_list.get(i);
            let imp: Impl* = hit.imp;
            for(let j = 0;j < imp.methods.len();++j){
                let m = imp.methods.get(j);       
                if(!m.name.eq(&sig.name)) continue;
                //record module scope for impls found via module search:
                //their idx addresses items inside that module, not top
                //level (see get_method).
                let desc_scope = Option<Type>::new();
                if(hit.scope.is_some()){
                    desc_scope.set(hit.scope.get().clone());
                }
                let desc = Desc{
                    kind: RtKind::MethodImpl{j},
                    path: m.path.clone(),
                    idx: hit.idx,
                    scope: desc_scope,
                };
                if(!scope_type.is_simple()){
                  list.add(Signature::new(m, desc, self.r, origin));
                  continue;
                }
                let scp_args = scope_type.get_args();
                if(scp_args.empty()){
                  let sig2 = Signature::new(m, &map, desc, self.r, origin);
                  if(hit.scope.is_some()){
                    //unscoped nested impl header (impl A in mod M): qualify
                    //its types (A) to the call scope (M::A) so check_args
                    //compares like with like.
                    let st = scope_type.as_simple();
                    if(st.scope.is_some() && imp.info.type.is_simple()
                        && imp.info.type.as_simple().scope.is_none()
                        && st.name.eq(imp.info.type.name().str())){
                      let qmap = HashMap<String, Type>::new();
                      qmap.add(imp.info.type.name().clone(), scope_type.clone());
                      let ac = AstCopier::new(&qmap);
                      for (let k = 0;k < sig2.args.len();++k) {
                        let arg = sig2.args.get(k);
                        let mapped = ac.visit(arg);
                        let tmp = sig2.args.set(k, mapped);
                        tmp.drop();
                      }
                      if(sig2.scope.is_some()){
                        let scp_mapped = ac.visit(&sig2.scope.get().type);
                        sig2.scope.get().type.drop();
                        sig2.scope.get().type = scp_mapped;
                      }
                      qmap.drop();
                    }
                  }
                  list.add(sig2);
                }else{
                  let typeMap = HashMap<String, Type>::new();
                  for(let k = 0;k < m.type_params.len();++k){
                    let ta = m.type_params.get(k);
                    typeMap.add(ta.name().clone(), scp_args.get(k).clone());
                  }
                  let sig2 = Signature::new(m, &map, desc, self.r, origin);
                  for (let k = 0;k < sig2.args.len();++k) {
                    let arg = sig2.args.get(k);
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
          let arr: List<Resolver*> = self.r.get_resolvers(false);
          for (let i = 0;i < arr.len();++i) {
            let resolver = *arr.get(i);
            resolver.init();
            let mr = MethodResolver::new(resolver);
            let err = mr.collect_member(sig, scope_type, list, false, origin);
            if (err.is_err()) {
                return Result<i32, String>::err(err.unwrap_err());
            }
          }
        }
        return Result<i32, String>::ok(0);
    }

    //one Item::Method / ExternItem::Method arm of collect_static: same
    //Desc shape, only the kind differs.
    func add_static_sig(self, m: Method*, idx: i32, kind: RtKind, name: str, list: List<Signature>*, origin: Resolver*){
        if (m.name.eq(name)) {
            let desc = Desc{
                kind: kind,
                path: m.path.clone(),
                idx: idx,
                scope: Option<Type>::new(),
            };
            list.add(Signature::new(m, desc, self.r, origin));
        }
    }
    func collect_static(self, name: str, list: List<Signature>*, origin: Resolver*){
        for (let i = 0;i < self.r.unit.items.len();++i) {
            let item: Item* = self.r.unit.items.get(i);
            if let Item::Method(m) = item{
                self.add_static_sig(m, i, RtKind::Method, name, list, origin);
            }
            else if let Item::Extern(arr) = item{
                for (let j = 0;j < arr.len();++j) {
                    let exi = arr.get(j);
                    if let ExternItem::Method(m)=exi{
                      self.add_static_sig(m, i, RtKind::MethodExtern{j}, name, list, origin);
                    }
                }
            }
        }
    }    

    func handle(self, expr: Expr*, sig: Signature*): RType{
        let mc = sig.mc.unwrap();
        let list_res = self.collect(sig);
        if(list_res.is_err()){
            self.r.err(expr, list_res.unwrap_err());
            panic("");
        }
        let list = list_res.unwrap();
        if(list.empty()){
            let msg = format("no such method {:?}", sig);
            self.r.err(expr, msg.str());
        }
        //test candidates and get errors
        let real = List<Signature*>::new();
        let errors = List<Pair<Signature*, String>>::new();
        let exact = Option<Signature*>::new();
        for(let i = 0;i < list.size();++i){
            let sig2 = list.get(i);
            let cmp_res: SigResult = self.is_same(sig, sig2);
            if let SigResult::Err(err) = cmp_res{
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
                let err: Pair<Signature*, String>* = errors.get(i);
                f.print(err.a);
                f.print(" ");
                f.print(&err.b);
                f.print("\n");
            }
            self.r.err(expr, f.unwrap());
        }
        if (real.size() > 1 && exact.is_none()) {
            let msg = format("method {:?} has {} candidates\n", mc, real.size());
            for(let i = 0;i < real.len();++i){
                let err: Signature* = *real.get(i);
                msg.append("\n  ");
                msg.append(err.print());
                msg.append(" ");
                msg.append(&err.m.unwrap_ptr().path);
            }
            self.r.err(expr, msg);
        }
        let target_sig = *real.get(0);
        if(exact.is_some()){
            target_sig = exact.unwrap();
        }
        let target: Method* = target_sig.m.unwrap();
        if (!target.is_generic) {
            if (!target.path.eq(&self.r.unit.path)) {
                self.r.addUsed(target);
            }
            let res = self.r.visit_type(&target.type);
            res.method_desc = Option::new(target_sig.desc.clone());
            return res;
        }
        let inferred_map = HashMap<String, Type>::new();
        let type_params = get_type_params(target);
        //place user given type args
        if (mc.scope.is_some() && mc.is_static) {
            if let Expr::Type(scp_type) = mc.scope.get(){
                if(scp_type.is_generic()){
                    //todo trait
                    //is static & have type args
                    let scope_args = scp_type.get_args();
                    if(scope_args.len() != type_params.len()){
                        self.r.err(expr, format("type args size mismatch {} vs {}", scope_args.len(), type_params.len()));
                    }
                    for (let i = 0; i < scope_args.size(); ++i) {
                        inferred_map.add(type_params.get(i).name().clone(), scope_args.get(i).clone());
                    }
                    //todo check type args if they compat with inferred ones
                }
            }
        }
        if (!mc.type_args.empty()) {
            //place specified type args in order
            for (let i = 0; i < mc.type_args.size(); ++i) {
                inferred_map.add(type_params.get(i).name().clone(), self.r.getType(mc.type_args.get(i)));
            }
        }
        //infer from args
        for (let k = 0; k < sig.args.size(); ++k) {
            let arg_type = sig.args.get(k);
            let target_type = target_sig.args.get(k);
            //case for self coerced to ptr
            if(k == 0 && !mc.is_static && target.self.is_some() && target_type.is_pointer() && !arg_type.is_pointer()){
                let arg2 = arg_type.clone().toPtr();
                let err = MethodResolver::infer(&arg2, target_type, &inferred_map, &type_params);
                if(err.is_err()){
                    self.r.err(expr, err.unwrap_err());
                }
                arg2.drop();
            }else{
                let err = MethodResolver::infer(arg_type, target_type, &inferred_map, &type_params);
                if(err.is_err()){
                    self.r.err(expr, err.unwrap_err());
                }
            }
        }
        for (let i = 0;i < type_params.len();++i) {
            let tp = type_params.get(i);
            if (!inferred_map.contains(tp.name())) {
                let msg = format("{:?}\ncan't infer type parameter: {:?}", sig, tp);
                self.r.err(expr, msg);
            }
        }
        if(sig.scope.is_some()){
            let ac = AstCopier::new(&inferred_map);
            let full_scope = ac.visit(&sig.scope.get().type);
            let scp_rt = sig.scope.get();
            scp_rt.type = full_scope;
        }
        let gen_pair: Pair<Method*, Desc> = self.generateMethod(&inferred_map, target, sig);
        let res = self.r.visit_type(&gen_pair.a.type);
        res.method_desc = Option::new(gen_pair.b);
        return res;
    }

    func infer(arg: Type*, prm: Type*, inferred: HashMap<String, Type>*, type_params: List<Type>*): Result<i32, String>{
        if(prm.is_simple() && type_params.contains(prm)){
            if(!inferred.contains(prm.name())){
                inferred.add(prm.name().clone(), arg.clone());
            }else{
                let inf = inferred.get(prm.name()).unwrap();
                let cmp = is_compatible(arg, inf);
                if(/*!inf.eq(arg)*/ cmp.is_some()){
                    let err = format("inferred type not compatible later {:?} vs {:?} but {:?}={:?}", arg, prm, prm, inf);
                    return Result<i32, String>::err(err);
                }
            }
            return Result<i32, String>::ok(0);
        }
        match arg{
            Type::Pointer(bx) => {
                if (!prm.is_pointer()){
                    return Result<i32, String>::err(format("prm is not ptr {:?} vs {:?}", arg, prm));
                }
                return infer(arg.elem(), prm.elem(), inferred, type_params);
            },
            Type::Slice(bx) => {
                if (!prm.is_slice()){
                    return Result<i32, String>::err("prm is not slice".owned());
                }
                return infer(arg.elem(), prm.elem(), inferred, type_params);
            },
            Type::Array(bx, size) => {
                if (!prm.is_array()) return Result<i32, String>::err("prm is not array".owned());
                return infer(arg.elem(), prm.elem(), inferred, type_params);
            },
            Type::Function(ft) => {
                if (!prm.is_fpointer()) return Result<i32, String>::err("prm is not func-ptr".owned());
                let ft1 = arg.get_ft();
                let ft2 = prm.get_ft();
                if(ft1.params.len() != ft2.params.len()){
                    return Result<i32, String>::err("arg size not match".owned());
                }
                let tmp = infer(&ft1.return_type, &ft2.return_type, inferred, type_params);
                if(tmp.is_err()) return tmp;
                for(let i = 0;i < ft1.params.len();++i){
                    let a1 = ft1.params.get(i);
                    let a2 = ft2.params.get(i);
                    let tmp2 = infer(a1, a2, inferred, type_params);
                    if(tmp2.is_err()) return tmp2;
                }
                return Result<i32, String>::ok(0);
            },
            Type::Lambda(lt) => {
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
                let tmp = infer(ft1.return_type.get(), &ft2.return_type, inferred, type_params);
                if(tmp.is_err()) return tmp;
                for(let i = 0;i < ft1.params.len();++i){
                    let a1 = ft1.params.get(i);
                    let a2 = ft2.params.get(i);
                    let tmp2 = infer(a1, a2, inferred, type_params);
                    if(tmp2.is_err()) return tmp2;
                }
                return Result<i32, String>::ok(0);
            },
            Type::Simple(smp) => {
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
                    for (let i = 0; i < ta1.len(); ++i) {
                        let ta = ta1.get(i);
                        let tp = ta2.get(i);
                        let tmp = infer(ta, tp, inferred, type_params);
                        if(tmp.is_err()) return tmp;
                    }
                }
                return Result<i32, String>::ok(0);
            },
            Type::Tuple(tt) => {
                match prm{
                    Type::Tuple(tt2) => {
                        if (tt.types.len() != tt2.types.len()) {
                            return Result<i32, String>::err(format("type count mismatch {:?} vs {:?}", tt.types.len(), tt2.types.len()));
                        }
                        for (let i = 0; i < tt.types.len(); ++i) {
                            let t1 = tt.types.get(i);
                            let t2 = tt2.types.get(i);
                            let tmp = infer(t1, t2, inferred, type_params);
                            if(tmp.is_err()) return tmp;
                        }
                    },
                    _ => {
                        return Result<i32, String>::err(format("prm is not tuple {:?} vs {:?}", arg, prm));
                    }
                }
                return Result<i32, String>::ok(0);
            }
        }
    }

    //exact-instantiation key: method identity + scope + inferred types in
    //canonical (type-param) order. Hit means bit-identical instantiation.
    func gen_key(m: Method*, sig: Signature*, map: HashMap<String, Type>*, type_params: List<Type>*): String{
        let f = Fmt::new();
        f.print(&m.path);
        f.print("#");
        f.print(&m.name);
        f.print("#");
        match &m.parent{
            Parent::Impl(info) => {
                f.print(&info.type);
            },
            Parent::Trait(ty) => {
                f.print(ty);
            },
            Parent::Module(qp) => {
                f.print(qp);
            },
            Parent::Extern => {
                f.print("extern");
            },
            Parent::None => {},
        }
        f.print("#");
        if(sig.scope.is_some()){
            f.print(&sig.scope.get().type);
        }
        f.print("#");
        if(sig.mc.unwrap().is_static){
            f.print("s");
        }else{
            f.print("i");
        }
        //method shape: overloads (new() vs new(cap)) share name, parent,
        //scope and inferred types, so the definition itself must be keyed.
        f.print("#");
        f.print(&m.type);
        if(m.self.is_some()){
            f.print("#self=");
            f.print(&m.self.get().type);
        }
        for(let i = 0;i < m.params.len();++i){
            f.print("#p=");
            f.print(&m.params.get(i).type);
        }
        for(let i = 0;i < type_params.len();++i){
            let tp = type_params.get(i);
            f.print("#");
            f.print(tp.name());
            f.print("=");
            let hit = map.get(tp.name());
            if(hit.is_some()){
                f.print(hit.unwrap());
            }
            hit.drop();
        }
        return f.unwrap();
    }

    func generateMethod(self, map: HashMap<String, Type>*, m: Method*, sig: Signature*): Pair<Method*, Desc>{
        let mc = sig.mc.unwrap();
        //fast path: exact (method, scope, inferred-types) key. Misses fall
        //through to the compatibility scan below (which also backfills).
        let tp_all = get_type_params(m);
        let key = gen_key(m, sig, map, &tp_all);
        {
            let cached = self.r.gen_cache.get(&key);
            if(cached.is_some()){
                let idx = cached.unwrap().idx;
                let arr = self.r.generated_methods.get(&m.name).unwrap();
                if(idx >= 0 && idx < arr.len()){
                    let gm = arr.get(idx).get();
                    let desc = cached.unwrap().clone();
                    return Pair::new(gm, desc);
                }
            }
        }
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
                        idx: i,
                        scope: Option<Type>::new(),
                    };
                    self.r.gen_cache.add(key.clone(), desc.clone());
                    tp_all.drop();
                    key.drop();
                    return Pair::new(gm.get(), desc);
                }
                ++i;
            }
        }
        let copier = AstCopier::new(map, &self.r.unit);
        let res2: Method = copier.visit(m);
        res2.is_generic = false;
        if(arr_opt.is_none()){
            self.r.generated_methods.add(m.name.clone(), List<Box<Method>>::new());
            arr_opt = self.r.generated_methods.get(&m.name);
        }
        let desc = Desc{
            kind: RtKind::MethodGen{m.name.clone()},
            path: self.r.unit.path.clone(),
            idx: arr_opt.unwrap().len() as i32,
            scope: Option<Type>::new(),
        };
        self.r.generated_methods_todo.add(desc.clone());
        let res: Method* = arr_opt.unwrap().add(Box::new(res2)).get();
        self.r.gen_cache.add(key, desc.clone());
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
            st = sig.args.get(0).deref_ptr().as_simple().clone();
        }
        //put full type, Box::new(...) -> Box<...>::new()
        let imp_args = imp.type.get_args();
        if (mc.is_static && !imp_args.empty()) {
            st.args.clear();
            for (let i = 0;i < imp_args.size();++i) {
                let ta = imp_args.get(i);
                let ta_str = ta.print();
                let resolved = map.get(&ta_str).unwrap();
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
                return SigResult::Err{"not same impl: slice vs non-slice".str()};
            }
            if(info.type_params.empty()){
                return SigResult::Err{"not same impl: slice not generic".str()};
            }
            let cmp = is_compatible(type1, type2, &info.type_params);
            if(cmp.is_some()){
                return SigResult::Err{"not same impl: slice incompatible".str()};
            }
            return SigResult::Exact;
            //panic("todo {} vs {}, mc={} cmp={}", type1, type2, sig.mc.unwrap(), &cmp);
        }
        if(!type1.is_simple() || !type2.is_simple()){
            return SigResult::Err{"not same impl kind".str()};
        }
        if (scope_rt.is_trait()) {
            let real_scope = sig.args.get(0).deref_ptr();
            if(info.trait_name.is_some()){
                if(!info.trait_name.get().name().eq(type1.name().str())){
                    return SigResult::Err{"not same trait".str()};
                }
                return SigResult::Exact;
            }
            else if (!real_scope.name().eq(type2.name())) {
                return SigResult::Err{"not same impl trait scope".str()};
            }
        }
        if(info.type_params.empty()){
            //unscoped nested impl header (impl A inside mod M, found via
            //module recursion): the search already verified membership, so
            //structural equality modulo the module scope is exact. Args
            //must still match (Option<X> is not Option<Y>).
            if(type1.is_simple() && type2.is_simple()){
                let s1 = type1.as_simple();
                let s2 = type2.as_simple();
                if(s2.scope.is_none() && s1.name.eq(&s2.name)
                    && s1.args.len() == s2.args.len()){
                    let same = true;
                    for(let k = 0;k < s1.args.len();++k){
                        if(!s1.args.get(k).eq_value(s2.args.get(k))){
                            same = false;
                            break;
                        }
                    }
                    if(same){
                        return SigResult::Exact;
                    }
                }
            }
            return SigResult::Err{"not same impl: not generic".str()};
        }
        if (!type1.name().eq(type2.name().str())) {
            return SigResult::Err{"not same impl name".str()};
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
                    let ta1 = mc_targs.get(i);
                    let ta2 = m.type_params.get(i);
                    if (!ta1.eq(ta2)) {
                        return SigResult::Err{"type arg not compatible".str()};
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
            let t1: Type = sig.args.get(i).clone();
            let t1p: Type* = sig.args.get(i);
            let t2: Type* = sig2.args.get(i);
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
            //exactness by structure (string compare would print both
            //types on every candidate; prints move into the error branch).
            if (!t1.eq_value(t2)) {
                all_exact = false;
            }
            let cmp: Option<String> = MethodResolver::is_compatible(&t1, t2, &typeParams);
            if (cmp.is_some()) {
                let t1_str = t1.print();
                let t2_str = t2.print();
                let arg = String::new();
                arg.drop();
                if(method.self.is_some()){
                    if(mc.is_static){
                        //sig2.args[0] is self, which static call syntax
                        //carries as scope, not as args[0] (off by one, and
                        //mc.args is empty for T::m() -> OOB).
                        if(i == 0){
                            arg = mc.scope.get().print();
                        }else{
                            arg = mc.args.get(i - 1).print();
                        }
                    }else{
                        arg = mc.scope.get().print();
                    }
                }else{
                    if(!mc.is_static && mc.scope.is_some()){
                        arg = mc.scope.get().print();
                    }else{
                        arg = mc.args.get(i).print();
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
            cmp.drop();
            t1.drop();
        }
        if(all_exact){
            return SigResult::Exact;
        }
        return SigResult::Compatible;
    }

    func is_compatible(arg: Type*, target: Type*): Option<String>{
        let typeParams = List<Type>::new();
        let arg_val = Option<String>::new();
        let res = MethodResolver::is_compatible(arg, &arg_val, target, &typeParams);
        return res;
    }
    func is_compatible(arg: Type*, target: Type*, typeParams: List<Type>*): Option<String>{
        let arg_val = Option<String>::new();
        let res = MethodResolver::is_compatible(arg, &arg_val, target, typeParams);
        return res;
    }

    func is_compatible(arg: Type*, arg_val: Option<String>*, target: Type*): Option<String>{
        let typeParams = List<Type>::new();
        let res = is_compatible(arg, arg_val, target, &typeParams);
        return res;
    }

    func is_compatible(arg: Type*, arg_val: Option<String>*, target: Type*, typeParams: List<Type>*): Option<String>{
        return is_compatible(arg, arg_val, target, typeParams, true);
    }

    func is_compatible_no_cast(arg: Type*, target: Type*): Option<String>{
        let typeParams = List<Type>::new();
        let res = is_compatible(arg, &Option<String>::new(), target, &typeParams, false);
        return res;
    }

    func is_compatible(arg: Type*, arg_val: Option<String>*, target: Type*, typeParams: List<Type>*, allow_cast: bool): Option<String>{
        if (typeParams.contains(target)) return Option<String>::new();
        if (arg.eq(target)) return Option<String>::new();
        match target{
            Type::Pointer(bx) => {
                if(!arg.is_pointer()){
                    return Option::new("arg is not pointer".str());
                }
                if(target.is_pointer()){
                    let trg_elem = target.elem();
                    return MethodResolver::is_compatible(arg.elem(), trg_elem, typeParams);
                }
                return Option::new("target is not pointer".str());
            },
            Type::Array(bx2, size2) => {
                if let Type::Array(bx, size) = arg{
                    if(*size != *size2){
                        return Option::new(format("element size mismatch {} vs {}", size, size2));
                    }
                    return is_compatible(arg.elem(), target.elem(), typeParams);
                }else{
                    return Option::new("arg is not array".str());
                }
            },
            Type::Slice(bx) => {
                if(!arg.is_slice()){
                    return Option::new("arg is not slice".str());
                }
                return is_compatible(arg.elem(), target.elem(), typeParams);
            },
            Type::Function(ft_bx) => {
                let ft2 = ft_bx.get();
                if(arg.is_lambda()){
                    let lm = arg.get_lambda();
                    if(!lm.captured.empty()){
                        return Option::new("has captured".str());
                    }
                    if(lm.return_type.is_some()){
                        let cmp = is_compatible(lm.return_type.get(), &ft2.return_type, typeParams);
                        if(cmp.is_some()){
                            return Option::new(format("ret mismatch {}", cmp.get()));
                        }
                    }else{
                        return Option::new("lambda has no ret".str());
                    }
                    if(ft2.params.len() != lm.params.len()){
                        return Option::new("arg count mismatch".str());
                    }
                    for(let i = 0;i < ft2.params.len();++i){
                        let cmp2 = MethodResolver::is_compatible(lm.params.get(i), ft2.params.get(i), typeParams);
                        if(cmp2.is_some()){
                            return cmp2;
                        }
                    }
                    return Option<String>::new();
                }else if(arg.is_fpointer()){
                    let ft1 = arg.get_ft();
                    let cmp1 = MethodResolver::is_compatible(&ft1.return_type, &ft2.return_type, typeParams);
                    if(cmp1.is_some()){
                        return cmp1;
                    }
                    if(ft1.params.len() != ft2.params.len()){
                        return Option::new("arg count mismatch".str());
                    }
                    for(let i = 0;i < ft1.params.len();++i){
                        let cmp2 = MethodResolver::is_compatible(ft1.params.get(i), ft2.params.get(i), typeParams);
                        if(cmp2.is_some()){
                            return cmp2;
                        }
                    }
                    return Option<String>::new();
                }else{
                    return Option::new("arg is not fpointer or lambda".str());
                }
            },
            Type::Lambda(lt) => {
                return Option::new("lambda parameter is not supported".owned());
            },
            Type::Simple(smp) =>{
                if (!arg.is_simple()) {
                    return Option::new("arg is not simple".str());
                }
            },
            Type::Tuple(tt2) => {
                match arg{
                    Type::Tuple(tt) => {
                        if (tt.types.len()!= tt2.types.len()) {
                            return Option::new("tuple size mismatch".str());
                        }
                        for(let i = 0;i < tt.types.len();++i){
                            let cmp = MethodResolver::is_compatible(tt.types.get(i), tt2.types.get(i), typeParams);
                            if(cmp.is_some()){
                                return cmp;
                            }
                        }
                    },
                    _ => {
                        return Option::new("arg is not tuple".str());
                    }
                }
            }
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
                if (arg.eq(target)) {
                    return Option<String>::new();
                } else {
                    return Option::new("type args don't match".str());
                }
            }
            //A<i32> and A<i64> not compatible
            for (let i = 0; i < targs.len(); ++i) {
                let ta = targs.get(i);
                let tp = targs2.get(i);
                let cmp = is_compatible(ta, tp, typeParams);
                if (cmp.is_some()) {
                    return cmp;
                }
                cmp.drop();
            }
            return Option<String>::new();
        }
        if (!target.is_prim()) return Option::new("target is not prim".str());
        if (arg.eq("bool") || target.eq("bool")) return Option::new("target is not bool".str());
        if (arg_val.is_some()) {
            //autocast literal
            let v: String* = arg_val.get();
            if (v.get(0) == '-') {
                if (isUnsigned(target)) {
                    return Option::new(format("{} is signed but {:?} is unsigned", v.str(), target));
                }
                //check range
            } else {
                if (max_for(target) >= i64::parse(v.str()).unwrap()) {
                    return Option<String>::new();
                } else {
                    return Option::new(format("{} can't fit into {:?}", v.str(), target));
                }
            }
        }
        if (isUnsigned(target) && isSigned(arg)) {
            return Option::new("arg is signed but target is unsigned".str());
        }
        // auto cast to larger size
        if (allow_cast && prim_size(arg.name().str()).unwrap() <= prim_size(target.name().str()).unwrap()){
            return Option<String>::new();
        }
        else {
            return Option::new(format("{:?} can't fit into {:?}", arg, target));
        }
    }

}

//true when the impl passes the optional trait filter (None = unscoped
//search, everything passes).
func trait_matches(imp: Impl*, tr: Option<Type*>): bool{
    if(tr.is_none()){
        return true;
    }
    if(imp.info.trait_name.is_none()){
        return false;
    }
    return imp.info.trait_name.get().eq(*tr.get());
}

//recursive module scan for get_impl: impls spelled with the full search
//scope but nested in a different module (impl M::A inside mod N, or deeper).
//prefix is the accumulated module path (owned, dropped at the end).
//Exact full-print matches only; unscoped searches never reach here.
func scan_mod_items(items: List<Item>*, prefix: Type, full: String*, tr: Option<Type*>, list: List<ImplHit>*){
    for(let i = 0;i < items.len();++i){
        let item = items.get(i);
        if let Item::Module(md) = item{
            let deeper = Type::new(prefix.clone(), md.name.clone());
            scan_mod_items(&md.items, deeper, full, tr, list);
            continue;
        }
        if(!(item is Item::Impl)) continue;
        let imp = item.as_impl();
        if(!trait_matches(imp, tr)){
            continue;
        }
        let imp_full = imp.info.type.print();
        if(full.eq(&imp_full)){
            list.add(ImplHit{imp: imp, idx: i, scope: Option::new(prefix.clone())});
        }
        imp_full.drop();
    }
}

func get_type_params(m: Method*): List<Type>{
    let res = List<Type>::new();
    if (!m.is_generic) {
        return res;
    }
    if let Parent::Impl(info) = &m.parent{
        res = info.type_params.clone();
    }
    res.add_list(m.type_params.clone());
    return res;
}

func hasGeneric(type: Type*, m: Method*): bool{
    let arr = get_type_params(m);
    let res = hasGeneric(type, &arr);
    return res;
}