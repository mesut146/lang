import parser/ast
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
    return scope.toPtr();
}

func replace_self(typ: Type*, m: Method*): Type{
    if(!typ.print().eq("Self")){
        return typ.clone();
    }
    if let Parent::Impl(info*)=(m.parent){
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
        res.add(tp.print(), *ta);
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
  let s = String::new();
  if let Parent::Impl(info*)=(m.parent){
    s.append(info.type.print().str());
    s.append("::");
  }else if let Parent::Trait(ty*)=(m.parent){
    s.append(ty.print().str());
    s.append("::");
  }else if let Parent::Extern=(m.parent){
    return m.name.clone();
  }
  s.append(m.name.str());
  for(let i=0;i<m.type_params.len();++i){
    let tp = m.type_params.get_ptr(i);
    s.append("_");
    s.append(tp.print().str());
  }
  if(m.self.is_some()){
    s.append("_");
    s.append(mangleType(&m.self.get().type).str());
  }
  for(let i=0;i<m.params.len();++i){
    let prm = m.params.get_ptr(i);
    s.append("_");
    s.append(mangleType(&prm.type).str());
  }
  return s;
}

func isReturnLast(b: Block*): bool{
    if(b.list.empty()) return false;
    let last = b.list.last();
    return isReturnLast(last);
  }
  
func isReturnLast(stmt: Stmt*): bool{
    if let Stmt::Block(b*)=(stmt){
        return isReturnLast(b);
    }
    if let Stmt::Expr(expr*)=(stmt){
        if let Expr::Call(mc*)=(expr){
        return mc.name.eq("panic");
        }
        return false;
    }
    return stmt is Stmt::Ret || stmt is Stmt::Continue || stmt is Stmt::Break;
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