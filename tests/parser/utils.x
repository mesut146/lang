import parser/ast
import parser/copier
import parser/printer
import std/map
import std/libc

func SLICE_PTR_INDEX(): i32{ return 0; }
func SLICE_LEN_INDEX(): i32{ return 1; }
func SLICE_LEN_BITS(): i32{ return 64; }
func ENUM_TAG_BITS(): i32{ return 64; }


func as_type(bits: i32): Type{
  if(bits == 64){
    return Type::new("i64");
  }
  return Type::new("i32");
}

func makeSelf(scope: Type*): Type{
    //if (scope.is_prim()) return *scope;
    return scope.clone().toPtr();
}

func replace_self(typ: Type*, m: Method*): Type{
    if(!typ.print().eq("Self")){
        return typ.clone();
    }
    if let Parent::Impl(info*)=(&m.parent){
        return info.type.clone();
    }
    panic("replace_self not impl method");
}

func get_type_map(type: Type*, decl: Decl*): Map<String, Type>{
    let res = Map<String, Type>::new();
    let targs = type.get_args();
    let type_params = decl.type.get_args();
    for(let i = 0;i < type_params.len();++i) {
        let ta = targs.get_ptr(i);
        let tp = type_params.get_ptr(i);
        res.add(tp.print(), ta.clone());
    } 
    return res;
}

func hasGeneric(type: Type*, typeParams: List<Type>*): bool{
    if (type.is_slice() || type.is_array() || type.is_pointer()) {
        let elem = type.elem();
        return hasGeneric(elem, typeParams);
    }
    if (!(type is Type::Simple)) panic("hasGeneric::Complex");
    let targs = type.get_args();
    if (targs.empty()) {
        for (let i = 0;i < typeParams.size();++i) {
            let tp = typeParams.get_ptr(i);
            let type_str = type.print();
            if (tp.print().eq(&type_str)) return true;
        }
    } else {
        for (let i = 0;i < targs.size();++i) {
            let ta = targs.get_ptr(i);
            if (hasGeneric(ta, typeParams)) return true;
        }
    }
    return false;
}

func isGeneric(typ: Type*, typeParams: List<Type>*): bool{
    if (!(typ is Type::Simple)) return false;
    if let Type::Simple(smp*) = (typ){
        if(smp.scope.is_some()){
            panic("isGeneric::scope");
        }
    }
    let targs = typ.get_args();
    if (targs.empty()) {
        for (let i = 0;i < typeParams.size();++i) {
            let type_str = typ.print();
            if (typeParams.get_ptr(i).print().eq(&type_str)) return true;
        }
    } else {
        for (let i = 0;i < targs.size();++i) {
            if (isGeneric(targs.get_ptr(i), typeParams)) return true;
        }
    }
    return false;
}

func isUnsigned(type: Type*): bool{
    let s = type.print();
    return s.eq("u8") || s.eq("u16") || s.eq("u32") || s.eq("u64");
}
func isSigned(type: Type*): bool{
    let s = type.print();
    return s.eq("i8") || s.eq("i16") || s.eq("i32") || s.eq("i64");
}

func max_for(type: Type*): i64{
    let s = type.print();
    let bits = prim_size(s).unwrap() as i32;
    let x = 1i64 << (bits - 1);
    if (isUnsigned(type)) {
        //do this not to overflow
        return x - 1 + x;
    }
    return x - 1;
}

//replace any type in decl with src by same index
func replace_type(type: Type*, map: Map<String, Type>*): Type {
    if let Type::Pointer(bx*) = (type){
        let scope = replace_type(bx.get(), map);
        let res = Type::Pointer{Box::new(scope)};
        return res;
    }
    if let Type::Array(bx*, size) = (type){
        let scope = replace_type(bx.get(), map);
        let res = Type::Array{Box::new(scope), size};
        return res;
    }
    if let Type::Slice(bx*) = (type){
        let scope = replace_type(bx.get(), map);
        let res = Type::Slice{Box::new(scope)};
        return res;
    }
    let str = type.print();
    if (map.contains(&str)) {
        return map.get_ptr(&str).unwrap().clone();
    }
    let smp = type.as_simple();
    let res = Simple::new(smp.name.clone());
    if (smp.scope.is_some()) {
        res.scope = Ptr::new(replace_type(smp.scope.get(), map));
    }
    for (let i = 0; i < smp.args.size(); ++i) {
        let ta = smp.args.get_ptr(i);
        res.args.add(replace_type(ta, map));
    }
    return res.into();
}

func is_struct(type: Type*): bool{
  return !type.is_prim() && !type.is_pointer() && !type.is_void(); 
}

func is_main(m: Method*): bool{
  return m.name.eq("main") && (m.params.empty() || m.params.len()==2);
}

func mangleType(type: Type*): String{
  let s = type.print();
  s = s.replace("*", "P");
  return s;
}

func mangle(m: Method*): String{
  if(is_main(m)) return m.name.clone();
  let s = Fmt::new();
  if let Parent::Impl(info*) = (&m.parent){
    s.print(&info.type);
    s.print("::");
  }else if let Parent::Trait(ty*) = (&m.parent){
    s.print(ty);
    s.print("::");
  }else if let Parent::Extern = (&m.parent){
    return m.name.clone();
  }
  s.print(&m.name);
  for(let i = 0;i < m.type_params.len();++i){
    let tp = m.type_params.get_ptr(i);
    s.print("_");
    s.print(tp);
  }
  if(m.self.is_some()){
    s.print("_");
    s.print(mangleType(&m.self.get().type).str());
  }
  for(let i = 0;i < m.params.len();++i){
    let prm = m.params.get_ptr(i);
    s.print("_");
    s.print(mangleType(&prm.type).str());
  }
  return s.unwrap();
}
func printMethod(m: Method*): String{
    let s = Fmt::new();
    if let Parent::Impl(info*)=(&m.parent){
      s.print(&info.type);
      s.print("::");
    }else if let Parent::Trait(type*)=(&m.parent){
      s.print(type);
      s.print("::");
    }
    s.print(&m.name);
    s.print("(");
    if(m.self.is_some()){
        //s.print(&m.self.get().type);
        if(m.self.get().is_deref){
            s.print("*");
        }
        s.print("self");
    }
    for(let i = 0;i < m.params.len();++i){
        let prm = m.params.get_ptr(i);
        if(i > 0 || m.self.is_some()) s.print(", ");
        s.print(&prm.type);
    }
    s.print(")");
    return s.unwrap();
  }
  
  //trait method signature for type
  func mangle2(m: Method*, type: Type*): String{
    let s = Fmt::new();
    s.print(&m.name);
    s.print("(");
    if(m.self.is_some()){
      s.print("_");
      s.print(type);
      s.print("*");
    }
    let map = Map<String, Type>::new();
    map.add("Self".str(), type.clone());
    let copier = AstCopier::new(&map);
    for(let i = 0;i < m.params.len();++i){
      s.print("_");
      let prm_type = &m.params.get_ptr(i).type;
      let mapped: Type = copier.visit(prm_type);
      s.print(&mapped);
      Drop::drop(mapped);
    }
    Drop::drop(map);
    s.print(")");
    return s.unwrap();
  }

func is_comp(s: str): bool{
    return s.eq("==") || s.eq("!=") || s.eq("<") || s.eq(">") || s.eq("<=") || s.eq(">=");
}

func is_str_lit(e: Expr*): Option<String*>{
    if let Expr::Lit(lit*)=(e){
        if(lit.kind is LitKind::STR){
            return Option::new(&lit.val);
        }
    }
    return Option<String*>::new();
}

func is_deref(expr: Expr*): Option<Expr*>{
    if let Expr::Unary(op*, e*)=(expr){
        if(op.eq("*")) return Option::new(e.get());
    }
    return Option<Expr*>::new();
}

enum ExitType {
    NONE,
    RETURN,
    PANIC,
    BREAK,
    CONTINE
}

struct Exit {
    kind: ExitType;
    if_kind: Ptr<Exit>;
    else_kind: Ptr<Exit>;
}

impl Exit{
    func new(kind: ExitType): Exit{
        return Exit{kind: kind, if_kind: Ptr<Exit>::new(), else_kind: Ptr<Exit>::new()};
    }
    func is_return(self): bool{
        if (self.kind is ExitType::RETURN) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_return() && self.else_kind.get().is_return();
        return false;
    }
    func is_panic(self): bool{
        if (self.kind is ExitType::PANIC) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_panic() && self.else_kind.get().is_panic();
        return false;
    }
    func is_exit(self): bool{
        if (self.kind is ExitType::RETURN || self.kind is ExitType::PANIC) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_exit() && self.else_kind.get().is_exit();
        return false;
    }
    func is_jump(self): bool{
        if (self.kind is ExitType::RETURN || self.kind is ExitType::PANIC || self.kind is ExitType::BREAK || self.kind is ExitType::CONTINE) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_jump() && self.else_kind.get().is_jump();
        return false;
    }
    func get_exit_type(block: Block*): Exit{
        if(block.list.empty()){
            return Exit::new(ExitType::NONE);
        }
        let last = block.list.last();
        return get_exit_type(last);
    }

    func get_exit_type(stmt: Stmt*): Exit{
        if(stmt is Stmt::Ret) return Exit::new(ExitType::RETURN);
        if(stmt is Stmt::Break) return Exit::new(ExitType::BREAK);
        if(stmt is Stmt::Continue) return Exit::new(ExitType::CONTINE);
        if let Stmt::Expr(expr*)=(stmt){
            if let Expr::Call(call*)=(expr){
                if(call.name.eq("panic")){
                    return Exit::new(ExitType::PANIC);
                }
            }
            return Exit::new(ExitType::NONE);
        }
        if let Stmt::Block(block*)=(stmt){
            let last = block.list.last();
            return get_exit_type(last);
        }
        if let Stmt::If(is*)=(stmt){
            let res = Exit::new(ExitType::NONE);
            res.if_kind = Ptr::new(get_exit_type(is.then.get()));
            if(is.els.is_some()){
                res.else_kind = Ptr::new(get_exit_type(is.els.get().get()));
            }
            return res;
        }
        return Exit::new(ExitType::NONE);
    }
}