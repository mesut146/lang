import parser/ast
import std/map

func makeSelf(scope: Type*): Type{
    if (scope.is_prim()) return *scope;
    return scope.toPtr();
}

func replace_self(typ: Type*, m: Method*): Type{
    if(!typ.print().eq("Self")){
        return *typ;
    }
    if let Parent::Impl(info*)=(m.parent){
        return info.type;
    }
    panic("replace_self not impl method");
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

//struct Generator{}

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
    if (map.has(&str)) {
        return *map.get_ptr(&str).unwrap();
    }
    let smp = type.as_simple();
    let res = Simple::new(smp.name);
    if (smp.scope.is_some()) {
        res.scope = Ptr::new(replace_type(smp.scope.get(), map));
    }
    for (let i = 0; i < smp.args.size(); ++i) {
        let ta = smp.args.get_ptr(i);
        res.args.add(replace_type(ta, map));
    }
    return res.into();
}