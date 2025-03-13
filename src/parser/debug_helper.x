import parser/bridge
import parser/ast
import parser/compiler
import parser/compiler_helper
import parser/resolver
import parser/utils
import parser/printer
import parser/ownership
import parser/own_model
import std/map
import std/libc
import std/stack

func base_class_name(): str{
  return "<super>";
}

struct DebugInfo{
    cu: DICompileUnit*;
    file: DIFile*;
    sp: Option<DISubprogram*>;
    types: Map<String, DIType*>;
    incomplete_types: Map<String, DICompositeType*>;
    debug: bool;
    scopes: Stack<DILexicalBlock*>;
}

func method_parent(m: Method*): Type*{
    if let Parent::Impl(info*)=(&m.parent){
        return &info.type;
    }
    if let Parent::Trait(type*)=(&m.parent){
        return type;
    }
    panic("method_parent");
}

impl DebugInfo{
    func new(path: str): DebugInfo{
        init_dbg();
        let path_c = CStr::new(path);
        let dir_c = CStr::new(".");
        let file = createFile(path_c.ptr(), dir_c.ptr());
        let cu = createCompileUnit(get_dwarf_cpp(), file);
        let debug = !getenv2("DEBUG").unwrap_or("1").eq("0");
        //print("debug={} env={}\n", debug, getenv2("DEBUG"));
        path_c.drop();
        dir_c.drop();
        return DebugInfo{cu: cu, file: file,
             sp: Option<DISubprogram*>::new(),
             types: Map<String, DIType*>::new(),
             incomplete_types: Map<String, DICompositeType*>::new(),
             debug: debug,
             scopes: Stack<DILexicalBlock*>::new()
        };
    }
    
    func finalize(self){
        if (!self.debug) return;
        finalizeSubprogram(self.sp.unwrap());
        self.sp = Option<DISubprogram*>::new();
    }

    func loc(self, line: i32, pos: i32) {
        if (!self.debug) return;
        if (self.sp.is_some()) {
            SetCurrentDebugLocation(self.get_scope(), line, pos);
        } else {
            panic("err no func for dbg");
            //SetCurrentDebugLocation(self.cu as DIScope*, line, pos);
        }
    }

    func dbg_func(self, m: Method*, f: Function*, c: Compiler*){
        if (!self.debug) return;
        let tys = vector_Metadata_new();
        vector_Metadata_push(tys, self.map_di(&m.type, c) as Metadata*);
        if(m.self.is_some()){
            let st = self.map_di(&m.self.get().type, c);
            vector_Metadata_push(tys, createObjectPointerType(st) as Metadata*);
        }
        for(let i = 0;i < m.params.len();++i){
            let prm = m.params.get_ptr(i);
            let pt = self.map_di(&prm.type, c);
            vector_Metadata_push(tys, pt as Metadata*);
        }
        let linkage_name = "".str();
        if(!is_main(m)){
            linkage_name.drop();
            linkage_name = mangle(m);
        }
        let path_c = m.path.clone().cstr();
        let file = createFile(path_c.ptr(), ".".ptr());
        path_c.drop();
        //self.file = file;
        let scope = file as DIScope*;
        if(!m.parent.is_none()){
            let parent = method_parent(m);
            scope = self.map_di(parent, c) as DIScope*;
        }
        let ft = createSubroutineType(tys);
        let flags = make_spflags(is_main(m));
        let name_c = m.name.clone().cstr();
        let linkage_c = linkage_name.cstr();
        let sp = createFunction(scope, name_c.ptr(), linkage_c.ptr(), file, m.line, ft, flags);
        setSubprogram(f, sp);
        self.sp = Option<DISubprogram*>::new(sp);
        self.loc(m.line, 0);
        name_c.drop();
        linkage_c.drop();
        vector_Metadata_delete(tys);
    }
    
    func dbg_prm(self, p: Param*, idx: i32, c: Compiler*) {
        if (!self.debug) return;
        let dt = self.map_di(&p.type, c);
        let scope = self.sp.unwrap() as DIScope*;
        let name_c = p.name.clone().cstr();
        let v = createParameterVariable(scope, name_c.ptr(), idx, self.file, p.line, dt, true);
        let val = *c.NamedValues.get(&p.name).unwrap();
        let lc = DILocation_get(scope, p.line, p.pos);
        insertDeclare(val, v, createExpression(), lc, GetInsertBlock());
        name_c.drop();
    }

    func dbg_var(self, name: String*, type: Type*, line: i32, c: Compiler*) {
      if (!self.debug) return;
      let dt = self.map_di(type, c);
      let scope = self.get_scope();
      let name_c = name.clone().cstr();
      let v = createAutoVariable(scope, name_c.ptr(), self.file, line, dt);
      let val = *c.NamedValues.get(name).unwrap();
      let lc = DILocation_get(scope, line, 0);
      insertDeclare(val, v, createExpression(), lc, GetInsertBlock());
      name_c.drop();
    }

    func dbg_glob(self, gl: Global*, ty: Type*, gv: GlobalVariable*, c: Compiler*): DIGlobalVariableExpression*{
      let scope = self.cu as DIScope*;
      let di_type = self.map_di(ty, c);
      let name_c = gl.name.clone().cstr();
      let gve = createGlobalVariableExpression(scope, name_c.ptr(), name_c.ptr(), self.file, gl.line, di_type);
      name_c.drop();
      addDebugInfo(gv, gve);
      return gve;
    }

    func get_scope(self): DIScope*{
      if(self.scopes.len() == 0){
        return self.sp.unwrap() as DIScope*;
      }
      return *self.scopes.top() as DIScope*;
    }

    func new_scope(self, line: i32)/*: DILexicalBlock**/{
      if(!self.debug) return;
      let scope = createLexicalBlock(self.get_scope(), self.file, line, 0);
      self.scopes.push(scope);
      //return scope;
    }
    func exit_scope(self){
      if(!self.debug) return;
      self.scopes.pop();
    }
    func new_scope(self, scope: DILexicalBlock*){
      if(!self.debug) return;
      self.scopes.push(scope);
    }

    func map_di_proto(self, decl: Decl*, c: Compiler*): DICompositeType*{
        let name: String = decl.type.print();
        let elems = vector_Metadata_new();
        let st_size = c.getSize(decl);
        let path_c = decl.path.clone().cstr();
        let name_c = name.clone().cstr();
        let file = createFile(path_c.ptr(), ".".ptr());
        let st = createStructType(self.cu as DIScope*, name_c.ptr(), file, decl.line, st_size, elems);
        self.incomplete_types.add(name, st);
        path_c.drop();
        name_c.drop();
        vector_Metadata_delete(elems);
        return st;
    }

    func make_variant_type(self, c: Compiler*, decl: Decl*, var_idx: i32, var_part: DICompositeType*, file: DIFile*, var_size: i64, scope: DICompositeType*, var_off: i64): DIDerivedType*{
      let ev = decl.get_variants().get_ptr(var_idx);
      let name: String = format("{:?}::{}", decl.type, ev.name.str());
      let var_type = c.protos.get().get(&name);
      let elems = vector_Metadata_new();
      //empty ty
      let name_c = name.clone().cstr();
      let st = createStructType(scope as DIScope*, name_c.ptr(), file, decl.line, var_size, elems);
      name_c.drop();
      //fill ty
      let sl = getStructLayout(var_type as StructType*);
      let idx = 0;
      if(decl.base.is_some()){
        let base_ty = self.map_di(decl.base.get(), c);
        let base_size = DIType_getSizeInBits(base_ty);
        let off = 0;
        let mem = createMemberType(st as DIScope*, base_class_name().ptr(), file, decl.line, base_size, off, make_di_flags(false), base_ty);
        vector_Metadata_push(elems, mem as Metadata*);
        ++idx;
      }
      for(let i = 0;i < ev.fields.len();++i){
        let fd = ev.fields.get_ptr(i);
        let fd_ty = self.map_di(&fd.type, c);
        let off = getElementOffsetInBits(sl, idx);
        let fd_size = DIType_getSizeInBits(fd_ty);
        let fdname_c = fd.name.clone().cstr();
        let mem = createMemberType(st as DIScope*, fdname_c.ptr(), file, decl.line, fd_size, off, make_di_flags(false), fd_ty);
        fdname_c.drop();
        vector_Metadata_push(elems, mem as Metadata*);
        ++idx;
      }
      replaceElements(st, elems);
      let evname_c = ev.name.clone().cstr();
      let res = createVariantMemberType(var_part as DIScope*, evname_c.ptr(), file, decl.line, var_size, var_off, var_idx, st as DIType*);
      evname_c.drop();
      name.drop();
      vector_Metadata_delete(elems);
      return res;
    }

    func map_di_fill(self, decl: Decl*, c: Compiler*): DIType*{
      let s = decl.type.print();
      let st = *self.incomplete_types.get_ptr(&s).unwrap();
      let path_c = decl.path.clone().cstr();
      let file = createFile(path_c.ptr(), ".".ptr());
      path_c.drop();
      let elems = vector_Metadata_new();
      let base_ty = Option<DIType*>::new();
      let scope = st as DIScope*;
      if(decl.base.is_some()){
        let ty = self.map_di(decl.base.get(), c);
        base_ty = Option<DIType*>::new(ty);
      }
      let st_real = c.mapType(&decl.type);
      //Type_dump(st_real);
      let sl = getStructLayout(st_real as StructType*);
      //print("st={} dl={}\n", getSizeInBits(st_real as StructType*), DataLayout_getTypeSizeInBits(st_real));
      if let Decl::Struct(fields*)=(decl){
        let idx = 0;
        if(decl.base.is_some()){
          let ty = *base_ty.get();
          let size = DIType_getSizeInBits(ty);
          let off = 0;
          let mem = createMemberType(scope, base_class_name().ptr(), file, decl.line, size, off, make_di_flags(false), ty);
          vector_Metadata_push(elems, mem as Metadata*);
          ++idx;
        }
        for(let i = 0;i < fields.len();++i){
          let fd = fields.get_ptr(i);
          let ty = self.map_di(&fd.type, c);
          let size = DIType_getSizeInBits(ty);
          let off = getElementOffsetInBits(sl, idx);
          let name_c = fd.name.clone().cstr();
          let mem = createMemberType(scope, name_c.ptr(), file, decl.line, size, off, make_di_flags(false), ty);
          vector_Metadata_push(elems, mem as Metadata*);
          ++idx;
          name_c.drop();
        }
      }else if let Decl::Enum(variants*)=(decl){
        let data_size = c.getSize(decl) - ENUM_TAG_BITS();
        let tag_off = 0i64;
        //create empty variant
        let tag_ty0: Type = as_type(ENUM_TAG_BITS());
        let tag = self.map_di(&tag_ty0, c);
        tag_ty0.drop();
        let disc = createMemberType(scope, "".ptr(), file, decl.line, data_size, tag_off, make_di_flags(true), tag);
        let elems2 = vector_Metadata_new();
        let var_part = createVariantPart(scope, "".ptr(), file, decl.line, data_size, disc, elems2);
        //fill variant
        let var_idx = 1;
        let var_off = getElementOffsetInBits(sl, var_idx);
        for(let i = 0;i < variants.len();++i){
          let ev = variants.get_ptr(i);
          let var_type = self.make_variant_type(c, decl, i, var_part, file, data_size, st, var_off);
          vector_Metadata_push(elems2, var_type as Metadata*);
        }
        replaceElements(var_part, elems2);
        vector_Metadata_push(elems, var_part as Metadata*);
        vector_Metadata_delete(elems2);
      }
      replaceElements(st, elems);
      self.types.add(s, st as DIType*);
      vector_Metadata_delete(elems);
      return st as DIType*;
    }

    func map_di(self, type: Type*, c: Compiler*): DIType*{
      let rt = c.get_resolver().visit_type(type);
      let name = rt.type.print();
      let res = self.map_di_resolved(&rt.type, &name, c);
      rt.drop();
      name.drop();
      return res;
    }

    func map_di_resolved(self, type: Type*, name: String*, c: Compiler*): DIType*{
      if(self.types.contains(name)){
        return *self.types.get_ptr(name).unwrap();
      }
      if(self.incomplete_types.contains(name)){
        return *self.incomplete_types.get_ptr(name).unwrap() as DIType*;
      }
      if(name.eq("void")) return get_di_null();
      if(name.eq("bool")){
        return createBasicType(name, 8, DW_ATE_boolean());
      }
      if(name.eq("i8") || name.eq("i16") || name.eq("i32") || name.eq("i64")){
        let size = c.getSize(type);
        return createBasicType(name, size, DW_ATE_signed());
      }
      if(name.eq("u8") || name.eq("u16") || name.eq("u32") || name.eq("u64")){
        let size = c.getSize(type);
        return createBasicType(name, size, DW_ATE_unsigned());
      }
      if(name.eq("f32") || name.eq("f64")){
        let size = c.getSize(type);
        return createBasicType(name, size, DW_ATE_float());
      }
      if(type.is_pointer()){
        let elem = type.elem();
        return createPointerType(self.map_di(elem, c), 64);
      }
      if let Type::Array(elem*, count)=(type){
        let elems = vector_Metadata_new();
        vector_Metadata_push(elems, getOrCreateSubrange(0, count));
        let elem_ty = self.map_di(elem.get(), c);
        let size = c.getSize(type);
        let res = createArrayType(size, elem_ty, elems);
        vector_Metadata_delete(elems);
        return res;
      }
      if let Type::Function(ft_box*)=(type){
        let tys = vector_Metadata_new();
        vector_Metadata_push(tys, self.map_di(&ft_box.get().return_type, c) as Metadata*);
        for prm in & ft_box.get().params{
          vector_Metadata_push(tys, self.map_di(prm, c) as Metadata*);
        }
        let sp = createSubroutineType(tys);
        vector_Metadata_delete(tys);
        return createPointerType(sp as DIType*, 64);
        //return sp as DIType*;
      }
      if let Type::Lambda(ft_box*)=(type){
        let tys = vector_Metadata_new();
        vector_Metadata_push(tys, self.map_di(ft_box.get().return_type.get(), c) as Metadata*);
        for prm in & ft_box.get().params{
          vector_Metadata_push(tys, self.map_di(prm, c) as Metadata*);
        }
        for prm in & ft_box.get().captured{
          vector_Metadata_push(tys, self.map_di(prm, c) as Metadata*);
        }
        let sp = createSubroutineType(tys);
        vector_Metadata_delete(tys);
        return createPointerType(sp as DIType*, 64);
        //return sp as DIType*;
      }
      if(type.is_slice()){
        let elem = type.elem();
        let size = c.getSize(type);
        let elems = vector_Metadata_new();
        let line = 0;
        //ptr
        let ptr_ty = createPointerType(self.map_di(elem, c), 64);
        let off = 0;
        let flags = make_di_flags(false);
        let ptr_mem = createMemberType(get_null_scope(), "ptr".ptr(), self.file, line, 64, off, flags, ptr_ty);
        vector_Metadata_push(elems, ptr_mem as Metadata*);
        //len
        let bits: Type = as_type(SLICE_LEN_BITS());
        let len_ty = self.map_di(&bits, c);
        bits.drop();
        let len_mem = createMemberType(get_null_scope(), "len".ptr(), self.file, line, SLICE_LEN_BITS(), 64, flags, len_ty);
        vector_Metadata_push(elems, len_mem as Metadata*);
        let name_c = name.clone().cstr();
        let res = createStructType(self.cu as DIScope*, name_c.ptr(), self.file, line, size, elems) as DIType*;
        name_c.drop();
        vector_Metadata_delete(elems);
        return res;
      }
      panic("map di {}\n", name);
    }
}

func createBasicType(name: String*, size: i64, enc: i32): DIType*{
  let name_c = name.clone().cstr();
  let res = createBasicType(name_c.ptr(), size, enc);
  name_c.drop();
  return res;
}