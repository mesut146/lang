import parser/bridge
import parser/ast
import parser/compiler
import parser/compiler_helper
import parser/resolver
import parser/utils
import std/map

struct DebugInfo{
    cu: DICompileUnit*;
    file: DIFile*;
    sp: Option<DISubprogram*>;
    types: Map<String, DIType*>;
    incomplete_types: Map<String, DICompositeType*>;
    debug: bool;
}

func method_parent(m: Method*): Type*{
    if let Parent::Impl(info*)=(m.parent){
        return &info.type;
    }
    if let Parent::Trait(type*)=(m.parent){
        return type;
    }
    panic("method_parent");
}

impl DebugInfo{
    func new(path: str): DebugInfo{
        init_dbg();
        let file = createFile(path.cstr(), ".".cstr());
        let cu = createCompileUnit(file);
        return DebugInfo{cu: cu, file: file,
             sp: Option<DISubprogram*>::new(),
             types: Map<String, DIType*>::new(),
             incomplete_types: Map<String, DICompositeType*>::new(),
             debug: false};
    }

    func loc(self, line: i32, pos: i32) {
        if (!self.debug) return;
        if (self.sp.is_some()) {
            SetCurrentDebugLocation(self.sp.unwrap() as DIScope*, line, pos);
        } else {
            SetCurrentDebugLocation(self.cu as DIScope*, line, pos);
        }
    }

    func dbg_func(self, m: Method*, f: Function*, c: Compiler*){
        if (!self.debug) return;
        let tys = Metadata_vector_new();
        Metadata_vector_push(tys, self.map_di(&m.type, c) as Metadata*);
        if(m.self.is_some()){
            let st = self.map_di(&m.self.get().type, c);
            Metadata_vector_push(tys, createObjectPointerType(st) as Metadata*);
        }
        for(let i=0;i<m.params.len();++i){
            let prm = m.params.get_ptr(i);
            let pt = self.map_di(&prm.type, c);
            Metadata_vector_push(tys, pt as Metadata*);
        }
        let linkage_name = "".str();
        if(!is_main(m)){
            linkage_name = mangle(m);
        }
        let file = createFile(m.path.cstr(), ".".cstr());
        //self.file = file;
        let scope = file as DIScope*;
        if(!m.parent.is_none()){
            let parent = method_parent(m);
            scope = self.map_di(parent, c) as DIScope*;
        }
        let ft = createSubroutineType(tys);
        let flags = make_spflags(is_main(m));
        let sp = createFunction(scope, m.name.cstr(), linkage_name.cstr(), file, m.line, ft, flags);
        setSubprogram(f, sp);
        //loc();
    }

    func map_di_proto(self, decl: Decl*, c: Compiler*): DICompositeType*{
        let name = decl.type.print();
        let elems = Metadata_vector_new();
        let st_size = c.getSize(decl);
        let file = createFile(decl.path.cstr(), ".".cstr());
        let st = createStructType(self.cu as DIScope*, name.cstr(), file, decl.line, st_size, elems);
        self.incomplete_types.add(name, st);
        return st;
    }


    func map_di(self, type: Type*, c: Compiler*): DIType*{
      let rt = c.resolver.visit(type);
      type = &rt.type;
      let name = type.print();
      if(self.types.contains(&name)){
        return self.types.get_p(&name).unwrap();
      }
      if(name.eq("void")) return get_di_null();
      if(name.eq("bool")){
        return createBasicType(name.cstr(), 8, DW_ATE_boolean());
      }
      if(name.eq("i8") || name.eq("i16") || name.eq("i32") || name.eq("i64")){
        let size = c.getSize(type);
        return createBasicType(name.cstr(), size, DW_ATE_signed());
      }
      if(name.eq("u8") || name.eq("u16") || name.eq("u32") || name.eq("u64")){
        let size = c.getSize(type);
        return createBasicType(name.cstr(), size, DW_ATE_unsigned());
      }
      if(name.eq("f32") || name.eq("f64")){
        let size = c.getSize(type);
        return createBasicType(name.cstr(), size, DW_ATE_float());
      }
      if(type.is_pointer()){
        let elem = type.elem();
        return createPointerType(self.map_di(elem, c), 64);
      }
      if let Type::Array(elem*, count)=(type){
        let elems = Metadata_vector_new();
        Metadata_vector_push(elems, getOrCreateSubrange(0, count));
        let elem_ty = self.map_di(elem.get(), c);
        let size = c.getSize(type);
        return createArrayType(size, elem_ty, elems);
      }
      if(type.is_slice()){
        let elem = type.elem();
        let size = c.getSize(type);
        let elems = Metadata_vector_new();
        let line = 0;
        //ptr
        let ptr_ty = createPointerType(self.map_di(elem, c), 64);
        let ptr_mem = createMemberType(get_null_scope(), "ptr".cstr(), self.file, line, 64, 0, ptr_ty);
        Metadata_vector_push(elems, ptr_mem as Metadata*);
        //len
        let bits = as_type(SLICE_LEN_BITS());
        let len_ty = self.map_di(&bits, c);
        let len_mem = createMemberType(get_null_scope(), "len".cstr(), self.file, line, SLICE_LEN_BITS(), 64, len_ty);
        Metadata_vector_push(elems, len_mem as Metadata*);
        return createStructType(self.cu as DIScope*, name.cstr(), self.file, line, size, elems) as DIType*;
      }
      panic("map di %s\n", name.cstr());
    }
}
