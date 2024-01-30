import parser/bridge
import parser/ast
import parser/resolver
import parser/compiler
import parser/utils
import std/map

func SLICE_LEN_BITS(): i32{ return 64; }
func ENUM_TAG_BITS(): i32{ return 64; }

func make_slice_type(): StructType*{
    let elems = make_vec();
    vec_push(elems, getPointerTo(getInt(8)));
    vec_push(elems, getInt(SLICE_LEN_BITS()));
    return make_struct_ty2("__slice".cstr(), elems);
}

func make_string_type(sliceType: llvm_Type*): StructType*{
    let elems = make_vec();
    vec_push(elems, sliceType);
    return make_struct_ty2("str".cstr(), elems);
}

func make_printf(): Function*{
    let args = make_vec();
    vec_push(args, getPointerTo(getInt(8)));
    let ft = make_ft(getInt(32), args, true);
    let f = make_func(ft, ext(), "printf".cstr());
    setCallingConv(f);
    return f;
}
func make_fflush(): Function*{
    let args = make_vec();
    vec_push(args, getPointerTo(getInt(8)));
    let ft = make_ft(getInt(32), args, false);
    let f = make_func(ft, ext(), "fflush".cstr());
    setCallingConv(f);
    return f;
}
func make_exit(): Function*{
    let args = make_vec();
    vec_push(args, getInt(32));
    let ft = make_ft(getVoidTy(), args, false);
    let f = make_func(ft, ext(), "exit".cstr());
    setCallingConv(f);
    return f;
}
func make_malloc(): Function*{
    let args = make_vec();
    vec_push(args, getInt(64));
    let ft = make_ft(getPointerTo(getInt(8)), args, false);
    let f = make_func(ft, ext(), "malloc".cstr());
    setCallingConv(f);
    return f;
}

func getTypes(unit: Unit*, list: List<Decl*>*){
    for (let i = 0;i < unit.items.len();++i) {
        let item = unit.items.get_ptr(i);
        if let Item::Decl(d*)=(item){
            if(d.is_generic) continue;
            list.add(d);
        }
    }
}

func sort(list: List<Decl*>*, r: Resolver*){
  for (let i = 0; i < list.len(); ++i) {
    //find min that belongs to i'th index
    let min = list.get(i);
    for (let j = i + 1; j < list.len(); ++j) {
      let cur = list.get(j);
      if (r.is_cyclic(&min.type, &cur.type)) {
        //print("swap " + min->type.print() + " and " + cur->type.print());
        min = cur;
        swap(list, i, j);
      }
    }
  }
}

func swap(list: List<Decl*>*, i: i32, j: i32){
  let a = list.get(i);
  let b = list.get(j);
  list.set(j, a);
  list.set(i, b);
}

func getMethods(unit: Unit*): List<Method*>{
  let list = List<Method*>::new();
  for (let i = 0;i < unit.items.len();++i) {
    let item = unit.items.get_ptr(i);
    if let Item::Method(m*)=(item){
        if(m.is_generic) continue;
        list.add(m);
    }else if let Item::Impl(imp*)=(item){
      if(!imp.info.type_params.empty()) continue;
      for(let j=0;j<imp.methods.len();++j){
        list.add(imp.methods.get_ptr(j));
      }
    }else if let Item::Extern(methods*)=(item){
      for(let j=0;j<methods.len();++j){
        list.add(methods.get_ptr(j));
      }
    }
  }
  return list;
}

func make_decl_proto(decl: Decl*): StructType*{
  //print("make_decl_proto %s\n", decl.type.print().cstr());
  return make_struct_ty(decl.type.print().cstr());
}

impl Compiler{
  func mapType(self, type: Type*): llvm_Type*{
    let p = self.protos.get();
    let r = self.resolver;
    let rt = r.visit(type);
    type = &rt.type;
    let s = type.print();
    //print("mapType %s\n", s.cstr());
    if(type.is_void()) return getVoidTy();
    let prim_size = prim_size(s.str());
    if(prim_size.is_some()){
      return getInt(prim_size.unwrap());
    }
    if let Type::Array(elem*,size)=(type){
      let elem_ty = self.mapType(elem.get());
      return getArrTy(elem_ty, size) as llvm_Type*;
    }
    if let Type::Slice(elem*)=(type){
      return p.std("slice") as llvm_Type*;
    }
    if let Type::Pointer(elem*)=(type){
      let elem_ty = self.mapType(elem.get());
      return getPointerTo(elem_ty);
    }
    if(!p.classMap.contains(&s)){
      p.dump();
      panic("mapType %s\n", s.cstr());
    }
    return p.get(&s);
  }

  func make_decl(self, decl: Decl*, st: StructType*){
    //print("make_decl %s\n", decl.type.print().cstr());
    let elems = make_vec();
    if(decl.base.is_some()){
      vec_push(elems, self.mapType(decl.base.get()));
    }
    if let Decl::Enum(variants*)=(decl){
      //calc enum size
      let max = 0;
      for(let i=0;i < variants.len();++i){
        let ev = variants.get_ptr(i);
        let var_ty = self.make_variant_type(ev,decl);
        let sz = getSizeInBits(var_ty);
        if(sz > max){
          max = sz;
        }
      }
      vec_push(elems, getInt(ENUM_TAG_BITS()));
      vec_push(elems, getArrTy(getInt(8), max / 8) as llvm_Type*);
    }else if let Decl::Struct(fields*)=(decl){
      if(fields.empty()) return;
      for(let i = 0;i < fields.len();++i){
        let fd = fields.get_ptr(i);
        let ft = self.mapType(&fd.type);
        vec_push(elems, ft);
      }
    }
    setBody(st, elems);
  }
  func make_variant_type(self, ev: Variant*, decl: Decl*): StructType*{
    let elems = make_vec();
    for(let j=0;j < ev.fields.len();++j){
      let fd = ev.fields.get_ptr(j);
      let ft = self.mapType(&fd.type);
      vec_push(elems, ft);
    }
    let name = Fmt::format("{}::{}",decl.type.print().str(), ev.name.str());
    return make_struct_ty2(name.cstr(), elems);
  }

  func make_proto(self, m: Method*){
    if(m.is_generic) return;
    let rvo = is_struct(&m.type);
    let ret = getVoidTy();
    if(is_main(m)){
      ret = getInt(32);
    }else if(!rvo){
      ret = self.mapType(&m.type);
    }
    let args = make_vec();
    if(rvo){
      let rvo_ty = getPointerTo(self.mapType(&m.type));
      vec_push(args, rvo_ty);
    }
    if(m.self.is_some()){
      let self_ty = self.mapType(&m.self.get().type);
      vec_push(args, self_ty);
    }
    for(let i=0;i<m.params.len();++i){
      let prm = m.params.get_ptr(i);
      let pt = self.mapType(&prm.type);
      if(is_struct(&prm.type)){
        pt = getPointerTo(pt);
      }
      vec_push(args, pt);
    }
    let ft = make_ft(ret, args, false);
    let linkage = ext();
    if(!m.type_args.empty()){
      linkage = odr();
    }
    let mangled = mangle(m);
    let f = make_func(ft, linkage, mangled.cstr());
    if(rvo){
      let arg = get_arg(f, 0);
      let sret = get_sret();
      arg_attr(arg, &sret);
    }
    self.protos.get().funcMap.add(mangled, f);
  }
}


func doesAlloc(e: Expr*, r: Resolver*): bool{
  if(e is Expr::Obj) return true;
  if let Expr::ArrAccess(aa*)=(e){
    return aa.idx2.is_some();//slice creation
  }
  if let Expr::Lit(kind*, val*, sf)=(e){
    return kind is LitKind::STR;
  }
  if let Expr::Type(ty*)=(e){
    return true;//enum creation
  }
  if let Expr::Array(list*,size)=(e){
    return true;
  }
  if let Expr::Call(call*)=(e){
    let target = r.visit(e).method;
    if(target.is_some()){
      return is_struct(&target.unwrap().type);
    }
  }
  panic("doesAlloc");
}