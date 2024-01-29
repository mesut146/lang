import parser/bridge
import parser/ast
import parser/resolver
import std/map

func SLICE_LEN_BITS(): i32{ return 64; }

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

func make_decl_proto(decl: Decl*): StructType*{
  return make_struct_ty(decl.type.print().cstr());
}

func make_decl(decl: Decl*, st: StructType*){
  if let Decl::Enum(variants*)=(decl){
  }else if let Decl::Struct(fields*)=(decl){
    let elems = make_vec();
    for(let i=0;i<fields.len();++i){
      let fd = fields.get_ptr(i);
      mapType(&fd.type);
    }
  }
}

func mapType(type: Type*): llvm_Type*{
  let s = type.print();
  panic("mapType %s\n", s.cstr());
}