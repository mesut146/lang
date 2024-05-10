import parser/bridge
import parser/ast
import parser/resolver
import parser/compiler
import parser/debug_helper
import parser/utils
import parser/printer
import std/map
import std/libc

func make_slice_type(): StructType*{
    let elems = make_vec();
    vec_push(elems, getPointerTo(getInt(8)));
    vec_push(elems, getInt(SLICE_LEN_BITS()));
    return make_struct_ty2("__slice".ptr(), elems);
}

func make_string_type(sliceType: llvm_Type*): StructType*{
    let elems = make_vec();
    vec_push(elems, sliceType);
    return make_struct_ty2("str".ptr(), elems);
}

func make_printf(): Function*{
    let args = make_vec();
    vec_push(args, getPointerTo(getInt(8)));
    let ft = make_ft(getInt(32), args, true);
    let f = make_func(ft, ext(), "printf".ptr());
    setCallingConv(f);
    return f;
}
func make_fflush(): Function*{
    let args = make_vec();
    vec_push(args, getPointerTo(getInt(8)));
    let ft = make_ft(getInt(32), args, false);
    let f = make_func(ft, ext(), "fflush".ptr());
    setCallingConv(f);
    return f;
}
func make_exit(): Function*{
    let args = make_vec();
    vec_push(args, getInt(32));
    let ft = make_ft(getVoidTy(), args, false);
    let f = make_func(ft, ext(), "exit".ptr());
    setCallingConv(f);
    return f;
}
func make_malloc(): Function*{
    let args = make_vec();
    vec_push(args, getInt(64));
    let ft = make_ft(getPointerTo(getInt(8)), args, false);
    let f = make_func(ft, ext(), "malloc".ptr());
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
    let min = *list.get_ptr(i);
    for (let j = i + 1; j < list.len(); ++j) {
      let cur = *list.get_ptr(j);
      if (r.is_cyclic(&min.type, &cur.type)) {
        //print("swap " + min->type.print() + " and " + cur->type.print());
        min = cur;
        swap(list, i, j);
      }
    }
  }
}

func swap(list: List<Decl*>*, i: i32, j: i32){
  let a = *list.get_ptr(i);
  let b = *list.get_ptr(j);
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
  return make_struct_ty(decl.type.print().cstr().ptr());
}

impl Compiler{
  func mapType(self, type: Type*): llvm_Type*{
    let p = self.protos.get();
    let r = self.resolver;
    let rt = r.visit(type);
    type = &rt.type;
    let s = type.print();
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
      panic("mapType {}\n", s);
    }
    return p.get(&s);
  }

  func make_decl(self, decl: Decl*, st: StructType*){
    let elems = make_vec();
    if(decl.base.is_some()){
      vec_push(elems, self.mapType(decl.base.get()));
    }
    if let Decl::Enum(variants*)=(decl){
      //calc enum size
      let max = 0;
      for(let i=0;i < variants.len();++i){
        let ev = variants.get_ptr(i);
        let name = format("{}::{}",decl.type, ev.name.str());
        let var_ty = self.make_variant_type(ev, decl, &name);
        self.protos.get().classMap.add(name, var_ty as llvm_Type*);
        let sz = getSizeInBits(var_ty);
        if(sz > max){
          max = sz;
        }
      }
      vec_push(elems, getInt(ENUM_TAG_BITS()));
      vec_push(elems, getArrTy(getInt(8), max / 8) as llvm_Type*);
    }else if let Decl::Struct(fields*)=(decl){
      //if(fields.empty()) return;
      for(let i = 0;i < fields.len();++i){
        let fd = fields.get_ptr(i);
        let ft = self.mapType(&fd.type);
        vec_push(elems, ft);
      }
    }
    setBody(st, elems);
    //Type_dump(st as llvm_Type*);
  }
  func make_variant_type(self, ev: Variant*, decl: Decl*, name: String*): StructType*{
    let elems = make_vec();
    for(let j=0;j < ev.fields.len();++j){
      let fd = ev.fields.get_ptr(j);
      let ft = self.mapType(&fd.type);
      vec_push(elems, ft);
    }
    return make_struct_ty2(name.clone().cstr().ptr(), elems);
  }

  func make_proto(self, m: Method*){
    if(m.is_generic) return;
    let mangled = mangle(m);
    //print("proto %s\n", mangled.cstr());
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
      if(is_struct(&m.self.get().type)){
        self_ty = getPointerTo(self_ty);
      }
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
    if(!m.type_params.empty()){
      linkage = odr();
    }else if let Parent::Impl(info*)=(&m.parent){
      if(info.type.is_simple() && !info.type.get_args().empty()){
        linkage = odr();
      }
    }

    let f = make_func(ft, linkage, mangled.clone().cstr().ptr());
    if(rvo){
      let arg = get_arg(f, 0);
      let sret = get_sret();
      arg_attr(arg, &sret);
    }
    if(self.protos.get().funcMap.contains(&mangled)){
      panic("already proto {}\n", mangled);
    }
    self.protos.get().funcMap.add(mangled, f);
  }

  func getSize(self, type: Type*): i64{
    if(type.is_prim()){
      return prim_size(type.name().str()).unwrap();
    }
    if(type.is_pointer()) return 64;
    if let Type::Array(elem*, sz)=(type){
      return self.getSize(elem.get()) * sz;
    }
    if let Type::Slice(elem*)=(type){
      let st = self.protos.get().std("slice");
      return getSizeInBits(st);
    }
    let rt = self.resolver.visit(type);
    if(rt.targetDecl.is_some()){
      let decl = rt.targetDecl.unwrap();
      return self.getSize(decl);
    }
    panic("getSize {}", type);
  }

  func getSize(self, decl: Decl*): i64{
    let mapped = self.mapType(&decl.type);
    return getSizeInBits(mapped as StructType*);
  }

  func cast(self, expr: Expr*, type: Type*): Value*{
    let val = self.loadPrim(expr);
    let val_ty = Value_getType(val);
    let src = getPrimitiveSizeInBits(val_ty);
    let trg = self.getSize(type);
    let trg_ty = getInt(trg as i32);
    let src_type = &self.resolver.visit(expr).type;
    if(src < trg){
      if(isUnsigned(src_type)){
        return CreateZExt(val, trg_ty);
      }else{
        return CreateSExt(val, trg_ty);
      }
    }else if(src > trg){
      return CreateTrunc(val, trg_ty);
    }
    return val;
  }

  func loadPrim(self, expr: Expr*): Value*{
    let val = self.visit(expr);
    let ty = Value_getType(val);
    if(!isPointerTy(ty)) return val;
    let type = self.getType(expr);
    return CreateLoad(self.mapType(&type), val);//local var
  }
  
  func setField(self, expr: Expr*, type: Type*, trg: Value*){
    if(is_struct(type)){
      let val = self.visit(expr);
      self.copy(trg, val, type);
    }else if(type.is_pointer()){
      let val = self.get_obj_ptr(expr);
      CreateStore(val, trg);
    }else{
      let val = self.cast(expr, type);
      CreateStore(val, trg); 
    }
  }

  //returns 1 bit for br
  func branch(self, expr: Expr*): Value*{
    let val = self.loadPrim(expr);
    return CreateTrunc(val, getInt(1));
  }
  //returns 1 bit for br
  func branch(self, val: Value*): Value*{
    return CreateTrunc(val, getInt(1));
  }

  func load(self, val: Value*, ty: Type*): Value*{
    let mapped = self.mapType(ty);
    return CreateLoad(mapped, val);
  }

  func get_obj_ptr(self, node: Expr*): Value*{
    if let Expr::Par(e*)=(node){
      return self.get_obj_ptr(e.get());
    }
    if let Expr::Unary(op*,e*)=(node){
      if(op.eq("*")){
        return self.visit(node);
      }
    }
    let val = self.visit(node);
    if(node is Expr::Obj || node is Expr::Call|| node is Expr::Lit || node is Expr::Unary || node is Expr::As){
      return val;
    }
    if(node is Expr::Name || node is Expr::ArrAccess || node is Expr::Access){
      let ty = self.getType(node);
      if(ty.is_pointer()){
        return CreateLoad(getPtr(), val);
      }
      return val;
    }
    panic("get_obj_ptr {}", node);
  }

  func getTag(self, expr: Expr*): Value*{
    let rt = self.resolver.visit(expr);
    let tag_idx = get_tag_index(rt.targetDecl.unwrap());
    let tag = self.get_obj_ptr(expr);
    let mapped = self.mapType(rt.type.unwrap_ptr());
    tag = self.gep2(tag, tag_idx, mapped);
    return CreateLoad(getInt(ENUM_TAG_BITS()), tag);
  }

  func get_variant_ty(self, decl: Decl*, variant: Variant*): llvm_Type*{
    let name = format("{}::{}", decl.type, variant.name.str());
    let res = *self.protos.get().classMap.get_ptr(&name).unwrap();
    Drop::drop(name);
    return res;
  }
}


func doesAlloc(e: Expr*, r: Resolver*): bool{
  if(e is Expr::Obj) return true;
  if let Expr::ArrAccess(aa*)=(e){
    return aa.idx2.is_some();//slice creation
  }
  if let Expr::Lit(lit*)=(e){
    return lit.kind is LitKind::STR;
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
    return false;
  }
  return false;
}

func getPrimitiveSizeInBits2(val: Value*): i32{
  let ty = Value_getType(val);
  return getPrimitiveSizeInBits(ty);
}

func gep_arr(type: llvm_Type*, ptr: Value*, i1: i32, i2: i32): Value*{
  let args = make_args();
  args_push(args, makeInt(i1, 64));
  args_push(args, makeInt(i2, 64));
  return CreateInBoundsGEP(type, ptr, args);
}

func gep_arr(type: llvm_Type*, ptr: Value*, i1: Value*, i2: Value*): Value*{
  let args = make_args();
  args_push(args, i1);
  args_push(args, i2);
  return CreateInBoundsGEP(type, ptr, args);
}

func gep_ptr(type: llvm_Type*, ptr: Value*, i1: Value*): Value*{
  let args = make_args();
  args_push(args, i1);
  return CreateGEP(type, ptr, args);
}


func get_tag_index(decl: Decl*): i32{
  if(decl.base.is_some()){
    return 1;
  }
  return 0;
}
func get_data_index(decl: Decl*): i32{
  return get_tag_index(decl) + 1;
}