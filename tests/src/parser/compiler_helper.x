import parser/bridge
import parser/ast

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