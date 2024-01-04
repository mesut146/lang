import parser/ast

func makeSelf(scope: Type*): Type{
    if (scope.is_prim()) return *scope;
    return scope.toPtr();
}

func hasGeneric(type: Type*, typeParams: List<Type>*): bool{
    if (type.is_slice() || type.is_array() || type.is_pointer()) {
        let elem = type.elem();
        return hasGeneric(&elem, typeParams);
    }
    if (!(type is Type::Simple)) panic("hasGeneric::Complex");
    let targs = type.get_args();
    if (targs.empty()) {
        for (let i = 0;i < typeParams.size();++i) {
            let tp = typeParams.get_ptr(i);
            if (tp.print().eq(type.print())) return true;
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
            if (typeParams.get_ptr(i).print().eq(typ.print())) return true;
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
