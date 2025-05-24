import std/hashmap
import std/libc
import std/io
import std/fs
import std/stack

import parser/ast
import parser/copier
import parser/printer

func SLICE_PTR_INDEX(): i32{ return 0; }
func SLICE_LEN_INDEX(): i32{ return 1; }
func SLICE_LEN_BITS(): i32{ return 64; }
func ENUM_TAG_BITS(): i32{ return 64; }

//T: Debug
func join_list<T>(arr: List<T>*): String{
    let f = Fmt::new();
    for(let i = 0;i < arr.len();++i){
        f.print(arr.get(i));
        if(i != arr.len() - 1){
            f.print(", ");
        }
    }
    return f.unwrap();
}

func as_type(bits: i32): Type{
  if(bits == 64){
    return Type::new("i64");
  }
  return Type::new("i32");
}

func hasGeneric(type: Type*, typeParams: List<Type>*): bool{
    match type{
        Type::Pointer(elem) => return hasGeneric(elem.get(), typeParams),
        Type::Array(elem, size) => return hasGeneric(elem.get(), typeParams),
        Type::Slice(elem) => return hasGeneric(elem.get(), typeParams),
        Type::Lambda(lt) => panic("internal err"),
        Type::Function(ft) => {
            if(hasGeneric(&ft.get().return_type, typeParams)){
                return true;
            }
            for prm in &ft.get().params{
                if(hasGeneric(prm, typeParams)){
                    return true;
                }
            }
            return false;
        },
        Type::Simple(smp) => {
            if (smp.args.empty()) {
                for (let i = 0;i < typeParams.size();++i) {
                    let tp = typeParams.get(i);
                    if (tp.eq(type)) return true;
                }
            } else {
                for (let i = 0;i < smp.args.size();++i) {
                    let ta = smp.args.get(i);
                    if (hasGeneric(ta, typeParams)) return true;
                }
            }
            return false;
        },
        Type::Tuple(tt) => {
            for ty in &tt.types{
                if(hasGeneric(ty, typeParams)){
                    return true;
                }
            }
            return false;
        }

    }
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


/*func demangle(input: str): String{
    let res = Fmt::new();
    let s = input.replace("$LT", "<");
    assign_eq(&s, s.replace("$GT", ">"));
    assign_eq(&s, s.replace("$P", "*"));
    assign_eq(&s, s.replace("__", "::"));
    res.print(&s);
    s.drop();
    return res.unwrap();
}*/

func mangleType(type: Type*, f: Fmt*){
    match type{
        Type::Pointer(elem) => {
            mangleType(elem.get(), f);
            f.print("$P");
        },
        Type::Slice(elem) => {
            f.print("[");
            mangleType(elem.get(), f);
            f.print("]");
        },
        Type::Array(elem, size) => {
            f.print("[");
            mangleType(elem.get(), f);
            f.print(";");
            Debug::debug(size, f);
            f.print("]");
        },
        Type::Function(ft0) => {
            let ft = ft0.get();
            f.print("func$LP");
            for prm in &ft.params{
                mangleType(prm, f);
            }
            f.print("$RP$AW");
            mangleType(&ft.return_type, f);  
        },
        Type::Lambda(lt0) =>{
            let lt = lt0.get();
            f.print("lambda$LP");
            for prm in &lt.params{
                mangleType(prm, f);
            }
            f.print("$RP");
            if(lt.return_type.is_some()){
                f.print("$AW");
                mangleType(lt.return_type.get(), f);
            }
        },
        Type::Tuple(tt) => {
            f.print("__tuple");
            for ty in &tt.types{
                f.print("_");
                mangleType(ty, f);
            }
        },
        Type::Simple(smp) => {
            if(smp.scope.is_some()){
                mangleType(smp.scope.get(), f);
                f.print("__");
            }
            f.print(&smp.name);
            if(!smp.args.empty()){
                f.print("$LT");
                for ta in &smp.args{
                    mangleType(ta, f);
                }
                f.print("$GT");
            }
        }
    }
}
func mangleType(type: Type*): String{
    let f = Fmt::new();
    mangleType(type, &f);
    return f.unwrap();
}

func mangle(m: Method*): String{
  if(is_main(m)) return m.name.clone();
  if(m.parent is Parent::Extern){
    return m.name.clone();
  }
  let f = Fmt::new();
  if let Parent::Impl(info) = &m.parent{
    mangleType(&info.type, &f);
    f.print("__");
  }else if let Parent::Trait(ty) = &m.parent{
    mangleType(ty, &f);
    f.print("__");
  }
  f.print(&m.name);
  if(m.type_params.len() > 0){
    f.print("$LT");
    for(let i = 0;i < m.type_params.len();++i){
        let tp = m.type_params.get(i);
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
    let prm = m.params.get(i);
    f.print("_");
    mangleType(&prm.type, &f);
  }
  return f.unwrap();
}

func printMethod(m: Method*): String{
    let s = Fmt::new();
    match &m.parent{
        Parent::Impl(info)=>{
            s.print(&info.type);
            s.print("::");
        },
        Parent::Trait(type)=>{
            s.print(type);
            s.print("::");
        },
        Parent::Module(name) => {
            s.print(name);
            s.print("::");
        },
        _=>{}
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
        let prm = m.params.get(i);
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
    let map = HashMap<String, Type>::new();
    map.add("Self".str(), type.clone());
    let copier = AstCopier::new(&map);
    for(let i = 0;i < m.params.len();++i){
      s.print("_");
      let prm_type = &m.params.get(i).type;
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
    if let Expr::Lit(lit)=e{
        if(lit.kind is LitKind::STR){
            return Option::new(&lit.val);
        }
    }
    return Option<String*>::new();
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