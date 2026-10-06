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

struct MethodSig{
    params: List<Type>;
    ret: Type;
}
impl MethodSig{
    func new(m: Method*, r: Resolver*): MethodSig{
        let params = List<Type>::new();
        let ret = r.getType(&m.type);
        if(m.self.is_some()){
            params.add(r.getType(&m.self.get().type));
        }
        for a in &m.params{
            params.add(r.getType(&a.type));
        }
        return MethodSig{params: params, ret: ret};
    }
}

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
    Err{s: String},
    Exact,
    Compatible
}

impl SigResult{
    func get_err(self): str{
        if let SigResult::Err(s)=self{
            return s.str();
        }
        panic("SigResult::get_err");
    }
}

//One impl candidate from get_impl. scope carries the module whose items
//idx addresses (None = top-level unit items); get_method resolves it
//(see get_method). Sibling-module hits (impl M::A inside mod N) record N.
#derive(Debug)
struct ImplHit{
  imp: Impl*;
  idx: i32;
  scope: Option<Type>;
}

impl Signature{
    func new(name: String): Signature{
        return Signature{
            mc: Option<Call*>::new(),
            m: Option<Method*>::new(),
            name: name,
            args: List<Type>::new(),
            scope: Option<RType>::new(),
            r: Option<Resolver*>::new(),
            desc: Desc::new()
        };
    }
    
    func new(mc: Call*, r: Resolver*): Signature{
        let res = Signature{
            mc: Option::new(mc),
            m: Option<Method*>::new(),
            name: mc.name.clone(),
            args: List<Type>::new(),
            scope: Option<RType>::new(),
            r: Option::new(r),
            desc: Desc::new()
        };
        let is_trait = false;
        if(mc.scope.is_some()){
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
                let inner = scp.type.deref_ptr();
                res.scope = Option::new(r.visit_type(inner));
                scp.drop();
            } else {
                res.scope = Option::new(scp);
            }
            if (!mc.is_static) {
                res.args.add(real_scope.get().type.clone());
            }
            real_scope.drop();
        }
        for(let i = 0;i < mc.args.len();++i){
            let arg = mc.args.get(i);
            let argt: RType = r.visit(arg);
            let type = argt.type.clone();
            argt.drop();
            res.args.add(type);
        }
        return res;
    }

    func make_inferred(sig: Signature*, type: Type*): HashMap<String, Type>{
        let map = HashMap<String, Type>::new();
        if(!type.is_simple()) return map;
        let type_plain: Type = type.erase();
        let decl_rt = sig.r.unwrap().visit_type(&type_plain);
        if(!decl_rt.is_decl()){
            //module scopes (M::useA) carry no type args to infer
            type_plain.drop();
            decl_rt.drop();
            return map;
        }
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
                let tp = args.get(i);
                map.add(tp.print(), args2.get(i).clone());
            }
        }
        return map;
    }
    func new(m: Method*, desc: Desc, r: Resolver*, origin: Resolver*): Signature{
        let map = HashMap<String, Type>::new();
        let res = Signature::new(m, &map, desc, r, origin);
        map.drop();
        return res;
    }
    func replace_self(typ: Type*, m: Method*): Type{
        if(!typ.eq("Self")){
            return typ.clone();
        }
        if let Parent::Impl(info)=&m.parent{
            return info.type.clone();
        }
        panic("replace_self not impl method");
    }
    func new(m: Method*, map: HashMap<String, Type>*, desc: Desc, r: Resolver*, origin: Resolver*): Signature{
        let res = Signature{
            mc: Option<Call*>::new(),
            m: Option<Method*>::new(m),
            name: m.name.clone(),
            args: List<Type>::new(),
            scope: Option<RType>::new(),
            r: Option<Resolver*>::new(r),
            desc: desc
        };
        if let Parent::Impl(info) = &m.parent{
            let scp = RType::new(info.type.clone());
            res.scope = Option::new(scp);
        }
        if(m.self.is_some()){
            res.args.add(m.self.get().type.clone());
        }
        let copier = AstCopier::new(map);
        for(let i = 0;i < m.params.len();++i){
            let prm = m.params.get(i);
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
            let arg: Type* = self.args.get(i);
            arg.debug(f);
        }
        f.print(")");
    }
}
