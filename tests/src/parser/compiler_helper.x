import parser/bridge
import parser/ast
import parser/resolver
import parser/compiler
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
    }else if let Item::Impl(info*, methods*)=(item){
      if(!info.type_params.empty()) continue;
      list.add(methods);
    }else if let Item::Extern(methods*)=(item){
      list.add(methods);
    }
  }
}

func make_decl_proto(decl: Decl*): StructType*{
  //print("make_decl_proto %s\n", decl.type.print().cstr());
  return make_struct_ty(decl.type.print().cstr());
}

func make_variant_type(p: Protos*,r: Resolver*, ev: Variant*, decl: Decl*): StructType*{
  let elems = make_vec();
  for(let j=0;j < ev.fields.len();++j){
    let fd = ev.fields.get_ptr(j);
    let ft = mapType(p, r, &fd.type);
    vec_push(elems, ft);
  }
  let name = Fmt::format("{}::{}",decl.type.print().str(), ev.name.str());
  return make_struct_ty2(name.cstr(), elems);
}

func make_decl(p: Protos*,r: Resolver*, decl: Decl*, st: StructType*){
  //print("make_decl %s\n", decl.type.print().cstr());
  let elems = make_vec();
  if(decl.base.is_some()){
    vec_push(elems, mapType(p, r, decl.base.get()));
  }
  if let Decl::Enum(variants*)=(decl){
    //calc enum size
    let max = 0;
    for(let i=0;i < variants.len();++i){
      let ev = variants.get_ptr(i);
      let var_ty = make_variant_type(p,r,ev,decl);
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
      let ft = mapType(p, r, &fd.type);
      vec_push(elems, ft);
    }
  }
  setBody(st, elems);
}

func mapType(p: Protos*, r: Resolver*, type: Type*): llvm_Type*{
  let rt = r.visit(type);
  type = &rt.type;
  let s = type.print();
  //print("mapType %s\n", s.cstr());
  let prim_size = prim_size(s.str());
  if(prim_size.is_some()){
    return getInt(prim_size.unwrap());
  }
  if let Type::Array(elem*,size)=(type){
    let elem_ty = mapType(p, r, elem.get());
    return getArrTy(elem_ty, size) as llvm_Type*;
  }
  if let Type::Slice(elem*)=(type){
    return p.sliceType as llvm_Type*;
  }
  if let Type::Pointer(elem*)=(type){
    let elem_ty = mapType(p, r, elem.get());
    return getPointerTo(elem_ty);
  }
  if(!p.classMap.contains(&s)){
    p.dump();
  }
  return p.get(&s);
  //panic("mapType %s\n", s.cstr());
}