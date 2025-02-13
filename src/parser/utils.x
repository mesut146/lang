import parser/ast
import parser/copier
import parser/printer
import parser/resolver
import std/map
import std/libc
import std/io
import std/stack

func SLICE_PTR_INDEX(): i32{ return 0; }
func SLICE_LEN_INDEX(): i32{ return 1; }
func SLICE_LEN_BITS(): i32{ return 64; }
func ENUM_TAG_BITS(): i32{ return 64; }

//T: Debug
func join_list<T>(arr: List<T>*): String{
    let f = Fmt::new();
    for(let i = 0;i < arr.len();++i){
        f.print(arr.get_ptr(i));
        if(i != arr.len() - 1){
            f.print(", ");
        }
    }
    return f.unwrap();
}

func get_filename(path: str): str{
    let idx = path.lastIndexOf("/");
    if(idx == -1){
        return path;
    }
    return path.substr(idx + 1);
}

func bin_name(path: str): String{
    let name = get_filename(path);
    return format("{}.bin", Path::noext(name));
}

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
    if(!typ.eq("Self")){
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
    if(type.is_fpointer()){
        let ft = type.get_ft();
        if(hasGeneric(&ft.return_type, typeParams)){
            return true;
        }
        for prm in &ft.params{
            if(hasGeneric(prm, typeParams)){
                return true;
            }
        }
        return false;
    }
    if (!(type is Type::Simple)) panic("hasGeneric::Complex {:?}", type);
    let targs = type.get_args();
    if (targs.empty()) {
        for (let i = 0;i < typeParams.size();++i) {
            let tp = typeParams.get_ptr(i);
            if (tp.eq(type)) return true;
        }
    } else {
        for (let i = 0;i < targs.size();++i) {
            let ta = targs.get_ptr(i);
            if (hasGeneric(ta, typeParams)) return true;
        }
    }
    return false;
}

func isGeneric2(typ: Type*, typeParams: List<Type>*): bool{
    for (let i = 0;i < typeParams.size();++i) {
        if (typeParams.get_ptr(i).eq(typ)) return true;
    }
    return false;
}

func isUnsigned(type: Type*): bool{
    let str = type.print();
    let res = str.eq("u8") || str.eq("u16") || str.eq("u32") || str.eq("u64");
    str.drop();
    return res;
}
func isSigned(type: Type*): bool{
    let str = type.print();
    let res = str.eq("i8") || str.eq("i16") || str.eq("i32") || str.eq("i64");
    str.drop();
    return res;
}

func is_less_than(){

}

func can_fit_into(val: str, target: Type*): bool{
    if(target.eq("f64")){
        //"179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368";
        return true;
    }
    if(target.eq("f32")){
        let max = "340282346638528859811704183484516925440";
        let trimmed = val;
        let comma = val.indexOf(".");
        if(comma != -1){
            trimmed = val.substr(0, val.indexOf("."));
        }
        if(trimmed.len() < max.len()){
            return true;
        }
        if(trimmed.len() > max.len()){
            return true;
        }
        let res = trimmed.cmp(max);
        //the both f32::max, compare after comma
        if(res == 0 && comma != -1){
            for(let i = comma + 1;i < val.len();++i){
                let chr = val.get(i);
                if(chr != '0'){
                    return false;
                }
            }
        }
        return res <= 0;
    }
    panic("can_fit_into todo {} -> {:?}", val, target);
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

func is_struct(type: Type*): bool{
  return !type.is_prim() && !type.is_pointer() && !type.is_void() && !type.is_fpointer() && !(type is Type::Lambda);
}

func is_loadable(type: Type*): bool{
    return type.is_prim() || type.is_pointer() || type.is_fpointer() || type is Type::Lambda;
  }

func is_main(m: Method*): bool{
  return m.name.eq("main") && (m.params.empty() || m.params.len() == 2);
}


func demangle(input: str): String{
    let res = Fmt::new();
    let s = input.replace("$LT", "<");
    assign_eq(&s, s.replace("$GT", ">"));
    assign_eq(&s, s.replace("$P", "*"));
    assign_eq(&s, s.replace("__", "::"));
    res.print(&s);
    s.drop();
    return res.unwrap();
}

func mangleType(type: Type*): String{
  let s = type.print();
  let s2 = s.replace("*", "$P");
  let s3 = s2.replace("<", "$LT");
  let s4 = s3.replace(">", "$GT");
  let s5 = s4.replace("::", "__");
  let s6 = s5.replace("(", "$LP");
  let s7 = s6.replace(")", "$RP");
  let s8 = s7.replace("=", "$EQ");
  let s9 = s8.replace(" ", "");
  s.drop();
  s2.drop();
  s3.drop();
  s4.drop();
  s5.drop();
  s6.drop();
  s7.drop();
  s8.drop();
  return s9;
}
func mangleType(type: Type*, f: Fmt*){
    let s = mangleType(type);
    f.print(&s);
    s.drop();
}

func mangle(m: Method*): String{
  if(is_main(m)) return m.name.clone();
  if(m.parent is Parent::Extern){
    return m.name.clone();
  }
  let f = Fmt::new();
  if let Parent::Impl(info*) = (&m.parent){
    mangleType(&info.type, &f);
    f.print("__");
  }else if let Parent::Trait(ty*) = (&m.parent){
    mangleType(ty, &f);
    f.print("__");
  }
  f.print(&m.name);
  if(m.type_params.len() > 0){
    f.print("$LT");
    for(let i = 0;i < m.type_params.len();++i){
        let tp = m.type_params.get_ptr(i);
        f.print("_");
        f.print(tp);
    }
    f.print("$GT");
  }
  if(m.self.is_some()){
    f.print("_");
    mangleType(&m.self.get().type, &f);
  }
  for(let i = 0;i < m.params.len();++i){
    let prm = m.params.get_ptr(i);
    f.print("_");
    mangleType(&prm.type, &f);
  }
  return f.unwrap();
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
      mapped.drop();
    }
    map.drop();
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
    BLOCK_RETURN,
    PANIC,
    BREAK,
    CONTINE,
    EXITCALL,
    UNREACHABLE
}

struct Exit {
    kind: ExitType;
    if_kind: Ptr<Exit>;
    else_kind: Ptr<Exit>;
    cases: List<Exit>;
}

impl Exit{
    func new(kind: ExitType): Exit{
        return Exit{
                      kind: kind,
                      if_kind: Ptr<Exit>::new(),
                      else_kind: Ptr<Exit>::new(),
                      cases: List<Exit>::new()
        };
    }
    func is_unreachable2(self): bool{
        for cs in &self.cases{
            if(!cs.is_unreachable()){
                return false;
            }
        }
        return true;
    }
    func is_return2(self): bool{
        for cs in &self.cases{
            if(!cs.is_return()){
                return false;
            }
        }
        return true;
    }
    func is_panic2(self): bool{
        for cs in &self.cases{
            if(!cs.is_panic()){
                return false;
            }
        }
        return true;
    }
    func is_exit2(self): bool{
        for cs in &self.cases{
            if(!cs.is_exit()){
                return false;
            }
        }
        return true;
    }
    func is_jump2(self): bool{
        for cs in &self.cases{
            if(!cs.is_jump()){
                return false;
            }
        }
        return true;
    }
    func is_none(self): bool{
        return self.kind is ExitType::NONE && self.if_kind.is_none() && self.else_kind.is_none() && self.cases.empty();
    }
    func is_unreachable(self): bool{
        if (self.kind is ExitType::UNREACHABLE) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_unreachable() && self.else_kind.get().is_unreachable();
        if(!self.cases.empty()) return self.is_unreachable2();
        return false;
    }
    func is_return(self): bool{
        if (self.kind is ExitType::RETURN) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_return() && self.else_kind.get().is_return();
        if(!self.cases.empty()) return self.is_return2();
        return false;
    }
    func is_panic(self): bool{
        if (self.kind is ExitType::PANIC) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_panic() && self.else_kind.get().is_panic();
        if(!self.cases.empty()) return self.is_panic2();
        return false;
    }
    func is_exit(self): bool{
        if (self.kind is ExitType::RETURN || self.kind is ExitType::PANIC || self.kind is ExitType::EXITCALL) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_exit() && self.else_kind.get().is_exit();
        if(!self.cases.empty()) return self.is_exit2();
        return false;
    }
    func is_jump(self): bool{
        if (self.kind is ExitType::RETURN || self.kind is ExitType::PANIC || self.kind is ExitType::BREAK || self.kind is ExitType::CONTINE || self.kind is ExitType::EXITCALL) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_jump() && self.else_kind.get().is_jump();
        if(!self.cases.empty()) return self.is_jump2();
        return false;
    }

    func get_exit_type(rhs: MatchRhs*): Exit{
        if let MatchRhs::EXPR(e*)=(rhs){
            return get_exit_type(e);
        }
        else if let MatchRhs::STMT(st*)=(rhs){
            return get_exit_type(st);
        }
        panic("unr");
    }

    func get_exit_type(body: Body*): Exit{
        if let Body::Block(b*)=(body){
            return get_exit_type(b);
        }
        else if let Body::If(val*)=(body){
            return get_exit_type(val);
        }
        else if let Body::IfLet(val*)=(body){
            return get_exit_type(val);
        }
        else if let Body::Stmt(val*)=(body){
            return get_exit_type(val);
        }
        else{
            panic("{:?}", body);
        }
    }

    func get_exit_type(block: Block*): Exit{
        if(block.return_expr.is_some()){
            let res = get_exit_type(block.return_expr.get());
            if(!res.is_none()){
                return res;
            }
            res.drop();
            return Exit::new(ExitType::BLOCK_RETURN);
        }
        if(block.list.empty()){
            return Exit::new(ExitType::NONE);
        }
        let last = block.list.last();
        return get_exit_type(last);
    }

    func get_exit_type(node: IfStmt*): Exit{
        let res = Exit::new(ExitType::NONE);
        res.if_kind = Ptr::new(get_exit_type(node.then.get()));
        if(node.else_stmt.is_some()){
            res.else_kind = Ptr::new(get_exit_type(node.else_stmt.get()));
        }
        return res;
    }

    func get_exit_type(node: IfLet*): Exit{
        let res = Exit::new(ExitType::NONE);
        res.if_kind = Ptr::new(get_exit_type(node.then.get()));
        if(node.else_stmt.is_some()){
            res.else_kind = Ptr::new(get_exit_type(node.else_stmt.get()));
        }
        return res;
    }
    
    func get_exit_type(node: Match*): Exit{
        let res = Exit::new(ExitType::NONE);
        for cs in &node.cases{
            res.cases.add(get_exit_type(&cs.rhs));
        }
        return res;
    }

    func get_exit_type(expr: Expr*): Exit{
        if let Expr::Call(call*)=(expr){
            if(call.name.eq("panic") && call.scope.is_none()){
                return Exit::new(ExitType::PANIC);
            }
            if(call.name.eq("exit") && call.scope.is_none()){
                return Exit::new(ExitType::EXITCALL);
            }
            if(Resolver::is_call(call, "std", "unreachable")){
                return Exit::new(ExitType::UNREACHABLE);
            }
        }
        if let Expr::Block(block0*)=(expr){
            let block = block0.get();
            return get_exit_type(block);
        }
        if let Expr::If(is0*)=(expr){
            let is = is0.get();
            return get_exit_type(is);
        }
        if let Expr::IfLet(iflet0*)=(expr){
            let iflet = iflet0.get();
            return get_exit_type(iflet);
        }
        if let Expr::Match(mt0*)=(expr){
            return get_exit_type(mt0.get());
        }
        return Exit::new(ExitType::NONE);
    }

    func get_exit_type(stmt: Stmt*): Exit{
        if(stmt is Stmt::Ret) return Exit::new(ExitType::RETURN);
        if(stmt is Stmt::Break) return Exit::new(ExitType::BREAK);
        if(stmt is Stmt::Continue) return Exit::new(ExitType::CONTINE);
        if let Stmt::Expr(expr*)=(stmt){
            return get_exit_type(expr);
        }
        return Exit::new(ExitType::NONE);
    }
}

func get_line(buf: str, line: i32): str{
    assert(line >= 1);
    let cur_line = 1;
    let pos = 0;
    while(pos < buf.len()){
      if(cur_line == line){
        let end = buf.indexOf("\n", pos);
        if(end == -1){
          end = buf.len() as i32;
        }
        return buf.substr(pos, end);
      }else{
        let i = buf.indexOf("\n", pos);
        if(i == -1){
    //todo
        }else{
          cur_line += 1;
          pos = i + 1;
        }
      }
    }
    panic("not possible");
  }