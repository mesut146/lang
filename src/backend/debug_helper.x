import std/libc
import std/stack
import std/hashmap
import std/io

import ast/ast
import ast/utils
import ast/printer

import resolver/resolver

//import backend/llvm
import backend/compiler
import backend/compiler_helper
import backend/bridge
import parser/ownership
import parser/own_model

func base_class_name(): str{
  return "super_";
}

struct DebugInfo{
    debug: bool;
    ll: Emitter2*;
    builder: DIBuilder*;
    cu: DICompileUnit*;
    file: DIFile*;
    sp: Option<DISubprogram*>;
    types: HashMap<String, DICompositeType*>;
    incomplete_types: HashMap<String, DICompositeType*>;
    scopes: Stack<DIScope*>;
    func_map: HashMap<String, DISubprogram*>;
}

func method_parent(m: Method*): Type*{
    match &m.parent{
      Parent::Impl(info) => return &info.type,
      Parent::Trait(type) => return type,
      _ => panic("method_parent"),
    }
}

impl DebugInfo{
    func new(debug: bool, path: str, ll: Emitter2*): DebugInfo{
        let builder = DIBuilder_new(ll.module);
        let path_c = CStr::new(path);
        let dir_c = CStr::new(".");
        let file = createFile(builder, path_c.ptr(), dir_c.ptr());
        let producer = "xlang";
        let flags = "";
        let split = "";
        let DWOId = 0;
        let sysroot = "";
        let sdk = "";
        let cu = createCompileUnit(builder, get_dwarf_cpp(), 
             file, producer.ptr());
        
        path_c.drop();
        dir_c.drop();
        return DebugInfo{
          debug: debug,
          ll: ll,
          builder: builder,
          cu: cu,
          file: file,
          sp: Option<DISubprogram*>::new(),
          types: HashMap<String, DICompositeType*>::new(),
          incomplete_types: HashMap<String, DICompositeType*>::new(),
          scopes: Stack<DIScope*>::new(),
          func_map: HashMap<String, DISubprogram*>::new(),
        };
    }
    
    func finalize(self){
        if (!self.debug) return;
        finalizeSubprogram(self.builder, self.sp.unwrap());
        self.sp = Option<DISubprogram*>::new();
    }

    func loc(self, line: i32, pos: i32) {
        if (!self.debug) return;
        if (self.sp.is_none()) {
          //SetCurrentDebugLocation(self.cu, line, pos);
          panic("err no func for dbg");
        }
        SetCurrentDebugLocation(self.ll.builder, self.get_scope(), line, pos);        
    }

    func dbg_func(self, m: Method*, f: Function*, c: Compiler*): Option<DISubprogram*>{
      if (!self.debug) return Option<DISubprogram*>::new();
      let sp = self.dbg_func_proto(m, c).unwrap();
      setSubprogram(f, sp);
      self.sp = Option<DISubprogram*>::new(sp);
      self.loc(m.line, 0);
      return Option::new(sp);
    }

    func dbg_func_proto(self, m: Method*, c: Compiler*): Option<DISubprogram*>{
        if (!self.debug) return Option<DISubprogram*>::new();
        let linkage_name = "".str();
        if(!is_main(m)){
          linkage_name.drop();
          linkage_name = mangle(m);
        }
        let opt = self.func_map.get(&linkage_name);
        if(opt.is_some()) return Option::new(*opt.unwrap());
        let tys = List<Metadata*>::new();
        tys.add(self.map_di(&m.type, c) as Metadata*);
        if(m.self.is_some()){
          let st = self.map_di(&m.self.get().type, c);
          tys.add(createObjectPointerType(st) as Metadata*);
        }
        for prm in &m.params{
          let pt = self.map_di(&prm.type, c);
          tys.add(pt as Metadata*);
        }
        let path_c = m.path.clone().cstr();
        let file = createFile(self.builder, path_c.ptr(), ".".ptr());
        path_c.drop();
        //self.file = file;
        let scope = file as DIScope*;
        if(!m.parent.is_none()){
          let parent = method_parent(m);
          scope = self.map_di(parent, c) as DIScope*;
        }
        let ft = createSubroutineType(self.builder, tys.ptr(), tys.len() as i32);
        let flags = SPFlagDefinition();
        if(is_main(m)){
          flags = flags | SPFlagMainSubprogram();
        }
        let name_c = m.name.clone().cstr();
        let linkage_name2 = linkage_name.clone();
        let linkage_c = linkage_name.cstr();
        let IsLocalToUnit = false;
        let IsDefinition = true;
        let scopeline = m.line;
        let IsOptimized = false;
        let sp = createFunction(self.builder, scope, name_c.ptr(), linkage_c.ptr(), file, m.line, ft, flags);
        self.func_map.add(linkage_name2, sp);
        name_c.drop();
        linkage_c.drop();
        tys.drop();
        return Option::new(sp);
    }
    
    func dbg_prm(self, p: Param*, idx: i32, c: Compiler*) {
        if (!self.debug) return;
        let dt = self.map_di(&p.type, c);
        if(p.is_self && p.is_deref){
          dt = createPointerType(self.builder, dt, 64);
        }
        let scope = self.sp.unwrap() as DIScope*;
        let name_c = p.name.clone().cstr();
        let AlwaysPreserve = true;
        let flags = DIFlags_FlagZero();
        if(p.is_self){
          flags = flags | DIFlags_FlagArtificial();
          flags = flags | DIFlags_FlagObjectPointer();
        }
        let v = createParameterVariable(self.builder, scope, name_c.ptr(), idx, self.file, p.line, dt, AlwaysPreserve, flags);
        let val = *c.NamedValues.get(&p.name).unwrap();
        let ex = createExpression(self.builder);
        let bb = GetInsertBlock(self.ll.builder);
        let loc = DILocation_get(self.builder, scope, p.line, p.pos);
        insertDeclare(self.builder, val, v, ex, loc, bb);
        name_c.drop();
    }

    func dbg_var(self, name: String*, type: Type*, line: i32, c: Compiler*) {
      if (!self.debug) return;
      let dt = self.map_di(type, c);
      let scope = self.get_scope();
      let name_c = name.clone().cstr();
      let v = createAutoVariable(self.builder, scope, name_c.ptr(), self.file, line, dt);
      let val = *c.NamedValues.get(name).unwrap();
      let ex = createExpression(self.builder);
      let bb = GetInsertBlock(self.ll.builder);
      let pos = 0;
      let loc = DILocation_get(self.builder, scope, line, pos);
      insertDeclare(self.builder, val, v, ex, loc, bb);
      name_c.drop();
    }

    func dbg_glob(self, gl: Global*, ty: Type*, gv: Value*, c: Compiler*): DIGlobalVariableExpression*{
      let scope = self.cu as DIScope*;
      let di_type = self.map_di(ty, c);
      let name_c = gl.name.clone().cstr();
      //let expr = createExpression(self.builder, ptr::null<i64>(), 0);
      //let decl = ptr::null<LLVMOpaqueMetadata>();
      let gve = createGlobalVariableExpression(self.builder, scope, name_c.ptr(), name_c.ptr(), self.file, gl.line, di_type);
      addDebugInfo(gv as GlobalVariable*, gve);
      name_c.drop();
      return gve;
    }

    func get_scope(self): DIScope*{
      if(self.scopes.len() == 0){
        return self.sp.unwrap() as DIScope*;
      }
      return *self.scopes.top();
    }

    func new_scope(self, line: i32)/*: LLVMOpaqueMetadata*/{
      if(!self.debug) return;
      let scope = createLexicalBlock(self.builder, self.get_scope(), self.file, line, 0);
      self.scopes.push(scope as DIScope*);
      //return scope;
    }
    func exit_scope(self){
      if(!self.debug) return;
      self.scopes.pop();
    }
    func new_scope(self, scope: DIScope*){
      if(!self.debug) return;
      self.scopes.push(scope);
    }

    func map_di_proto(self, decl: Decl*, c: Compiler*): DICompositeType*{
        let name: String = decl.type.print();
        let elems = [ptr::null<Metadata>(); 0];
        let st_size = c.getSize(decl);
        let path_c = decl.path.clone().cstr();
        let name_c = name.clone().cstr();
        let file = createFile(self.builder, path_c.ptr(), ".".ptr());
        let flags = 0;
        let st = createStructType(self.builder, self.ll.ctx, self.cu as DIScope*, name_c.ptr(), file, decl.line, st_size, elems.ptr(), elems.len() as i32);
        self.incomplete_types.add(name, st);
        path_c.drop();
        name_c.drop();
        return st;
    }

    func make_variant_type(self, c: Compiler*, decl: Decl*, var_idx: i32, var_part: DICompositeType*, file: DIFile*, var_size: i64, scope: DIScope*, var_off: i64): DIDerivedType*{
      let ev = decl.get_variants().get(var_idx);
      let name: String = format("{:?}::{}", decl.type, ev.name.str());
      let var_type = c.protos.get().get(&name) as StructType*;
      let elems = List<Metadata*>::new();
      //empty ty
      let name_c = name.clone().cstr();
      let flags=0;
      //fill ty
      let sl = getStructLayout(var_type);
      let idx = 0;
      let scp = ptr::null<DIScope>();
      if(decl.base.is_some()){
        let base_ty = self.map_di(decl.base.get(), c);
        let base_size = DIType_getSizeInBits(base_ty);
        let off = 0;
        let flagsm = 0;
        let mem = createMemberType(self.builder, scp, base_class_name().ptr(), file, decl.line, base_size, off, flagsm, base_ty);
        elems.add(mem as Metadata*);
        ++idx;
      }
      let fi = 0;
      for fd in &ev.fields{
        let fd_ty = self.map_di(&fd.type, c);
        let off = getElementOffsetInBits(sl, idx);
        let fd_size = DIType_getSizeInBits(fd_ty);
        let fdname_c = if (fd.name.is_some()){
          fd.name.get().clone().cstr()
        }else{
          format("_{}", fi).cstr()
        };
        let flagsm = 0;
        let mem = createMemberType(self.builder, scp, fdname_c.ptr(), file, decl.line, fd_size, off, flagsm, fd_ty);
        fdname_c.drop();
        elems.add(mem as Metadata*);
        ++idx;
        ++fi;
      }
      let st = createStructType(self.builder, self.ll.ctx, scope, name_c.ptr(), file, decl.line, var_size, elems.ptr(), elems.len() as i32);
      
      let evname_c = ev.name.clone().cstr();
      let flagsm=0;
      let res = createMemberType(self.builder, var_part as DIScope*, evname_c.ptr(), file, decl.line, var_size, var_off, flagsm, st as DIType*);//var_idx?
      evname_c.drop();
      name.drop();
      elems.drop();
      name_c.drop();
      return res;
    }

    func find_impl(ty: Type*, r: Resolver*): List<Impl*>{
      let res = List<Impl*>::new();
      for it in &r.unit.items{
        if let Item::Impl(imp) = it{
          if(imp.info.type.eq(ty)){
            res.add(imp);
          }
        }
      }
      return res;
    }

    func fill_funcs_member(self, decl: Decl*, c: Compiler*, elems: List<Metadata*>*){
      if(decl.type.is_generic()) return;
      if(decl.type.is_simple() && decl.type.as_simple().scope.is_some()){
        //todo
        return;
      }
      let imps: List<Pair<Impl*, i32>> = MethodResolver::get_impl(c.get_resolver(), &decl.type, Option<Type*>::new()).unwrap();
      for pr in imps{
        for fun in &pr.a.methods{
          if(fun.is_generic) continue;
          let proto = self.dbg_func_proto(fun, c).unwrap();
          elems.add(proto as Metadata*);
        }
      }
    }

    func map_di_fill(self, decl: Decl*, c: Compiler*): DICompositeType*{
      let s = decl.type.print();
      let st = *self.incomplete_types.get(&s).unwrap();
      let path_c = decl.path.clone().cstr();
      let file = createFile(self.builder, path_c.ptr(), ".".ptr());
      path_c.drop();
      let elems = List<Metadata*>::new();
      let base_ty = Option<DIType*>::new();
      let scope = st as DIScope*;
      if(decl.base.is_some()){
        let ty = self.map_di(decl.base.get(), c);
        base_ty = Option::new(ty);
      }
      let st_real = c.mapType(&decl.type);
      let sl = getStructLayout(st_real as StructType*);
      //let dl = LLVMGetModuleDataLayout(self.ll.module);
      match decl{
        Decl::Struct(fields)=>{
          let idx = 0;
          if(decl.base.is_some()){
            let ty = *base_ty.get();
            let size = DIType_getSizeInBits(ty);
            let off = 0;
            let mem = createMemberType(self.builder, scope, base_class_name().ptr(), file, decl.line, size, off, 0, ty);
            elems.add(mem as Metadata*);
            ++idx;
          }
          let fi = 0;
          for fd in fields{
            let ty = self.map_di(&fd.type, c);
            let size = DIType_getSizeInBits(ty);
            let off = getElementOffsetInBits(sl, idx);
            let name_c = if(fd.name.is_some()){
              fd.name.get().clone().cstr()
            }else{
              format("_{}", fi).cstr()
            };
            let mem = createMemberType(self.builder, scope, name_c.ptr(), file, decl.line, size, off, 0, ty);
            elems.add(mem as Metadata*);
            ++idx;
            ++fi;
            name_c.drop();
          }
          self.fill_funcs_member(decl, c, &elems);
        },
        Decl::TupleStruct(fields)=>{
          let idx = 0;
          for fd in fields{
            let ty = self.map_di(&fd.type, c);
            let size = DIType_getSizeInBits(ty);
            let off = getElementOffsetInBits(sl, idx);
            let name_c = format("_{}", idx).cstr();
            let mem = createMemberType(self.builder, scope, name_c.ptr(), file, decl.line, size, off, 0, ty);
            elems.add(mem as Metadata*);
            ++idx;
            name_c.drop();
          }
          self.fill_funcs_member(decl, c, &elems);
        },
        Decl::Enum(variants)=>{
          let data_size = c.getSize(decl) - ENUM_TAG_BITS();
          let tag_off = 0i64;
          //create empty variant
          let tag_ty0: Type = as_type(ENUM_TAG_BITS());
          let tag = self.map_di(&tag_ty0, c);
          tag_ty0.drop();
          let fldesc = DIFlags_FlagArtificial();
          let disc = createMemberType(self.builder, scope, "".ptr(), file, decl.line, data_size, tag_off, fldesc, tag);
          let elems2 = List<Metadata*>::new();
          let var_part = createVariantPart(self.builder, scope, "".ptr(), file, decl.line, data_size, disc, elems2.ptr(), elems2.len() as i32);
          
          //fill variant
          let var_idx = 1;
          let var_off = getElementOffsetInBits(sl, var_idx);
          for(let i = 0;i < variants.len();++i){
            let ev = variants.get(i);
            let var_type = self.make_variant_type(c, decl, i, var_part, file, data_size, st as DIScope*, var_off);
            elems2.add(var_type as Metadata*);
          }
          replaceElements(var_part, elems2.ptr(), elems2.len() as i32);
          elems.add(var_part as Metadata*);
          elems2.drop();
        },
      }
      replaceElements(st, elems.ptr(), elems.len() as i32);
      self.types.add(s, st);
      elems.drop();
      return st;
    }

    func map_di(self, type: Type*, c: Compiler*): DIType*{
      let rt = c.get_resolver().visit_type(type);
      let name = rt.type.print();
      let res = self.map_di_resolved(&rt.type, &name, c);
      rt.drop();
      name.drop();
      return res;
    }

    func struct_ty(self, name: str, line: i32, size: i32, elems: [Metadata*]): DICompositeType*{
      let name_c = name.cstr();
      let flags = 0;
      let RunTimeLang = 0;
      let res = createStructType(self.builder, self.ll.ctx, self.cu as DIScope*, name_c.ptr(), self.file, line, size, elems.ptr(), elems.len() as i32);
      name_c.drop();
      return res;
    }

    func map_di_resolved(self, type: Type*, name: String*, c: Compiler*): DIType*{
      let opt1 = self.types.get(name);
      if(opt1.is_some()){
        return *opt1.unwrap() as DIType*;
      }
      let opt2 = self.incomplete_types.get(name);
      if(opt2.is_some()){
        return *opt2.unwrap() as DIType*;
      }
      match type{
        Type::Pointer(elem) => {
          let nameptr = "";
          return createPointerType(self.builder, self.map_di(elem.get(), c), 64) as DIType*;
        },
        Type::Array(elem, count)=>{
          let elems = [getOrCreateSubrange(self.builder, 0, *count)];
          let elem_ty = self.map_di(elem.get(), c);
          let size = c.getSize(type);
          let align = 0;
          let res = createArrayType(self.builder, size, elem_ty, elems.ptr(), elems.len() as i32);
          return res as DIType*;
        },
        Type::Function(ft_box)=>{
          let tys = List<Metadata*>::new();
          tys.add(self.map_di(&ft_box.get().return_type, c) as Metadata*);
          for prm in & ft_box.get().params{
            tys.add(self.map_di(prm, c) as Metadata*);
          }
          let file = self.file;
          let spt = createSubroutineType(self.builder, tys.ptr(), tys.len() as i32);
          let nameptr = "";
          tys.drop();
          return createPointerType(self.builder, spt as DIType*, 64) as DIType*;
        },
        Type::Lambda(ft_box) => {
          let tys = List<Metadata*>::new();
          tys.add(self.map_di(ft_box.get().return_type.get(), c) as Metadata*);
          for prm in & ft_box.get().params{
            tys.add(self.map_di(prm, c) as Metadata*);
          }
          for prm in & ft_box.get().captured{
            tys.add(self.map_di(prm, c) as Metadata*);
          }
          let spt = createSubroutineType(self.builder, tys.ptr(), tys.len() as i32);
          tys.drop();
          let nameptr = "";
          return createPointerType(self.builder, spt as DIType*, 64) as DIType*;
        },
        Type::Slice(elem)=>{
          let nameptr = "";
          let size = c.getSize(type);
          let line = 0;
          let scp = ptr::null<DIScope>();
          //ptr
          let ptr_ty = createPointerType(self.builder, self.map_di(elem.get(), c), 64);
          let off = 0;
          let flags = 0;
          let ptr_mem = createMemberType(self.builder, scp, "ptr".ptr(), self.file, line, 64, off, flags, ptr_ty);
          //len
          let bits: Type = as_type(SLICE_LEN_BITS());
          let len_ty = self.map_di(&bits, c);
          bits.drop();
          let len_mem = createMemberType(self.builder, scp, "len".ptr(), self.file, line, SLICE_LEN_BITS(), 64, flags, len_ty);
          let name_c = "_slice".cstr();
          let elems = [ptr_mem as Metadata*, len_mem as Metadata*];
          let flags2 = DIFlags_FlagZero();
          let RunTimeLang = 0;
          let res = createStructType(self.builder, self.ll.ctx, self.cu as DIScope*, name_c.ptr(), self.file, line, size, elems.ptr(), elems.len() as i32);
          name_c.drop();
          return res as DIType*;
        },
        Type::Tuple(tt) => {
          let name_c = mangleType(type).cstr();
          let line = 0;
          let size = c.getSize(type);
          let elems = List<Metadata*>:: new();
          let idx = 0;
          let ty = c.mapType(type) ;
          let sl = getStructLayout(ty as StructType*);
          for elem in &tt.types{
            let elem_di = self.map_di(elem, c);
            let off = getElementOffsetInBits(sl, idx);
            let flags2 = DIFlags_FlagZero();
            let elem_name = format("_{}", idx).cstr();
            let mem = createMemberType(self.builder, ptr::null<DIScope>(), elem_name.ptr(), self.file, line, size, off, flags2, elem_di);
            elems.add(mem as Metadata*);
            ++idx;
            elem_name.drop();
          }
          let res = createStructType(self.builder, self.ll.ctx, self.cu as DIScope*, name_c.ptr(), self.file, line, size, elems.ptr(), elems.len() as i32);
          name_c.drop();
          elems.drop();
          return res as DIType*;
        },
        Type::Simple(smp)=>{
          if(name.eq("void")) return ptr::null<DIType>();
          if(name.eq("bool")){
            return self.createBasicType(name, 8, DW_ATE_boolean()) as DIType*;
          }
          if(name.eq("i8") || name.eq("i16") || name.eq("i32") || name.eq("i64")){
            let size = c.getSize(type);
            return self.createBasicType(name, size, DW_ATE_signed()) as DIType*;
          }
          if(name.eq("u8") || name.eq("u16") || name.eq("u32") || name.eq("u64")){
            let size = c.getSize(type);
            return self.createBasicType(name, size, DW_ATE_unsigned()) as DIType*;
          }
          if(name.eq("f32") || name.eq("f64")){
            let size = c.getSize(type);
            return self.createBasicType(name, size, DW_ATE_float()) as DIType*;
          }
          //already mapped
          panic("map di {}\n", name);
        }
      }
    }

    func createBasicType(self, name: String*, size: i64, enc: i32): DIType*{
      let name_c = name.clone().cstr();
      let res = createBasicType(self.builder, name_c.ptr(), size, enc);
      name_c.drop();
      return res;
    }
}
