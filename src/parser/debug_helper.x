import std/libc
import std/stack
import std/hashmap
import std/io

import ast/ast
import ast/utils
import ast/printer

import resolver/resolver

import parser/llvm
import parser/compiler
import parser/compiler_helper
import parser/ownership
import parser/own_model

func base_class_name(): str{
  return "super_";
}

struct DebugInfo{
    debug: bool;
    ll: Emitter*;
    builder: LLVMOpaqueDIBuilder*;
    cu: LLVMOpaqueMetadata*;
    file: LLVMOpaqueMetadata*;
    sp: Option<LLVMOpaqueMetadata*>;
    types: HashMap<String, LLVMOpaqueMetadata*>;
    incomplete_types: HashMap<String, LLVMOpaqueMetadata*>;
    scopes: Stack<LLVMOpaqueMetadata*>;
    func_map: HashMap<String, LLVMOpaqueMetadata*>;
}

func method_parent(m: Method*): Type*{
    match &m.parent{
      Parent::Impl(info) => return &info.type,
      Parent::Trait(type) => return type,
      _ => panic("method_parent"),
    }
}

impl DebugInfo{
    func new(debug: bool, path: str, ll: Emitter*): DebugInfo{
        let builder = LLVMCreateDIBuilder(ll.module);
        let path_c = CStr::new(path);
        let dir_c = CStr::new(".");
        let file = LLVMDIBuilderCreateFile(builder, path_c.ptr(), path_c.len(), dir_c.ptr(), dir_c.len());
        let producer = "xlang";
        let flags = "";
        let split = "";
        let DWOId = 0;
        let sysroot = "";
        let sdk = "";
        let cu = LLVMDIBuilderCreateCompileUnit(builder, LLVMDWARFSourceLanguage::LLVMDWARFSourceLanguageC_plus_plus{}.int(), 
             file, producer.ptr(), producer.len(), LLVMBoolFalse(), 
            flags.ptr(), flags.len(),
           1, split.ptr(), split.len(), 
          LLVMDWARFEmissionKind::LLVMDWARFEmissionFull{}.int(),
         DWOId, LLVMBoolFalse(), LLVMBoolFalse(), 
        sysroot.ptr(), sysroot.len(), sdk.ptr(), sdk.len());
        
        path_c.drop();
        dir_c.drop();
        return DebugInfo{
          debug: debug,
          ll: ll,
          builder: builder,
          cu: cu,
          file: file,
          sp: Option<LLVMOpaqueMetadata*>::new(),
          types: HashMap<String, LLVMOpaqueMetadata*>::new(),
          incomplete_types: HashMap<String, LLVMOpaqueMetadata*>::new(),
          scopes: Stack<LLVMOpaqueMetadata*>::new(),
          func_map: HashMap<String, LLVMOpaqueMetadata*>::new(),
        };
    }
    
    func finalize(self){
        if (!self.debug) return;
        LLVMDIBuilderFinalizeSubprogram(self.builder, self.sp.unwrap());
        self.sp = Option<LLVMOpaqueMetadata*>::new();
    }

    func loc(self, line: i32, pos: i32) {
        if (!self.debug) return;
        if (self.sp.is_none()) {
          //SetCurrentDebugLocation(self.cu, line, pos);
          panic("err no func for dbg");
        }
        let loc = LLVMDIBuilderCreateDebugLocation(self.ll.ctx, line, pos, self.get_scope(), ptr::null<LLVMOpaqueMetadata>());
        LLVMSetCurrentDebugLocation2(self.ll.builder, loc);        
    }

    func dbg_func(self, m: Method*, f: LLVMOpaqueValue*, c: Compiler*): Option<LLVMOpaqueMetadata*>{
      if (!self.debug) return Option<LLVMOpaqueMetadata*>::new();
      let sp = self.dbg_func_proto(m, c).unwrap();
      LLVMSetSubprogram(f, sp);
      self.sp = Option<LLVMOpaqueMetadata*>::new(sp);
      self.loc(m.line, 0);
      return Option::new(sp);
    }

    func dbg_func_proto(self, m: Method*, c: Compiler*): Option<LLVMOpaqueMetadata*>{
        if (!self.debug) return Option<LLVMOpaqueMetadata*>::new();
        let linkage_name = "".str();
        if(!is_main(m)){
          linkage_name.drop();
          linkage_name = mangle(m);
        }
        let opt = self.func_map.get(&linkage_name);
        if(opt.is_some()) return Option::new(*opt.unwrap());
        let tys = List<LLVMOpaqueMetadata*>::new();
        tys.add(self.map_di(&m.type, c));
        if(m.self.is_some()){
          let st = self.map_di(&m.self.get().type, c);
          tys.add(LLVMDIBuilderCreateObjectPointerType(self.builder, st, LLVMBoolFalse()));
        }
        for prm in &m.params{
          let pt = self.map_di(&prm.type, c);
          tys.add(pt);
        }
        let path_c = m.path.clone().cstr();
        let file = LLVMDIBuilderCreateFile(self.builder, path_c.ptr(), path_c.len(), ".".ptr(), 1);
        path_c.drop();
        //self.file = file;
        let scope = file;
        if(!m.parent.is_none()){
          let parent = method_parent(m);
          scope = self.map_di(parent, c);
        }
        let ft = LLVMDIBuilderCreateSubroutineType(self.builder, file, tys.ptr(), tys.len() as i32, LLVMDIFlags::LLVMDIFlagZero{}.int());
        let flags = DISPFlags::SPFlagDefinition{}.int();
        if(is_main(m)){
          flags = flags | DISPFlags::SPFlagMainSubprogram{}.int();
        }
        let name_c = m.name.clone().cstr();
        let linkage_name2 = linkage_name.clone();
        let linkage_c = linkage_name.cstr();
        let IsLocalToUnit = LLVMBoolFalse();
        let IsDefinition = LLVMBoolTrue();
        let scopeline = m.line;
        let IsOptimized = LLVMBoolFalse();
        let sp = LLVMDIBuilderCreateFunction(self.builder, scope, name_c.ptr(), name_c.len(), linkage_c.ptr(), linkage_c.len(), file, m.line, ft, IsLocalToUnit, IsDefinition, scopeline, flags, IsOptimized);
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
          dt = LLVMDIBuilderCreatePointerType(self.builder, dt, 64, 0, 0, "".ptr(), 0);
        }
        let scope = self.sp.unwrap();
        let name_c = p.name.clone().cstr();
        let AlwaysPreserve = LLVMBoolTrue();
        let flags = LLVMDIFlags::LLVMDIFlagZero{}.int();
        if(p.is_self){
          flags = flags | LLVMDIFlags::LLVMDIFlagArtificial{}.int();
          flags = flags | LLVMDIFlags::LLVMDIFlagObjectPointer{}.int();
        }
        let v = LLVMDIBuilderCreateParameterVariable(self.builder, scope, name_c.ptr(), name_c.len(), idx, self.file, p.line, dt, AlwaysPreserve, flags);
        let val = *c.NamedValues.get(&p.name).unwrap();
        let lc = LLVMDIBuilderCreateDebugLocation(self.ll.ctx, p.line, p.pos, scope, ptr::null<LLVMOpaqueMetadata>());
        LLVMDIBuilderInsertDeclareRecordAtEnd(self.builder, val, v, LLVMDIBuilderCreateExpression(self.builder, ptr::null<i64>(), 0), lc, LLVMGetInsertBlock(self.ll.builder));
        name_c.drop();
    }

    func dbg_var(self, name: String*, type: Type*, line: i32, c: Compiler*) {
      if (!self.debug) return;
      let dt = self.map_di(type, c);
      let scope = self.get_scope();
      let name_c = name.clone().cstr();
      let AlwaysPreserve = LLVMBoolTrue();
      let flags = LLVMDIFlags::LLVMDIFlagZero{}.int();
      let v = LLVMDIBuilderCreateAutoVariable(self.builder, scope, name_c.ptr(), name_c.len(), self.file, line, dt, AlwaysPreserve, flags, 0);
      let val = *c.NamedValues.get(name).unwrap();
      let lc = LLVMDIBuilderCreateDebugLocation(self.ll.ctx, line, 0, scope, ptr::null<LLVMOpaqueMetadata>());
      LLVMDIBuilderInsertDeclareRecordAtEnd(self.builder, val, v, LLVMDIBuilderCreateExpression(self.builder, ptr::null<i64>(), 0), lc, LLVMGetInsertBlock(self.ll.builder));
      name_c.drop();
    }

    func dbg_glob(self, gl: Global*, ty: Type*, gv: LLVMOpaqueValue*, c: Compiler*): LLVMOpaqueMetadata*{
      let scope = self.cu;
      let di_type = self.map_di(ty, c);
      let name_c = gl.name.clone().cstr();
      let expr = LLVMDIBuilderCreateExpression(self.builder, ptr::null<i64>(), 0);
      let decl = ptr::null<LLVMOpaqueMetadata>();
      let gve = LLVMDIBuilderCreateGlobalVariableExpression(self.builder, scope, name_c.ptr(), name_c.len(), name_c.ptr(), name_c.len(), self.file, gl.line, di_type, LLVMBoolFalse(), expr, decl, 0);
      name_c.drop();
      //LLVMAddMetadataToGlobal(gv, , gve);
      return gve;
    }

    func get_scope(self): LLVMOpaqueMetadata*{
      if(self.scopes.len() == 0){
        return self.sp.unwrap();
      }
      return *self.scopes.top();
    }

    func new_scope(self, line: i32)/*: LLVMOpaqueMetadata*/{
      if(!self.debug) return;
      let scope = LLVMDIBuilderCreateLexicalBlock(self.builder, self.get_scope(), self.file, line, 0);
      self.scopes.push(scope);
      //return scope;
    }
    func exit_scope(self){
      if(!self.debug) return;
      self.scopes.pop();
    }
    func new_scope(self, scope: LLVMOpaqueMetadata*){
      if(!self.debug) return;
      self.scopes.push(scope);
    }

    func map_di_proto(self, decl: Decl*, c: Compiler*): LLVMOpaqueMetadata*{
        let name: String = decl.type.print();
        let elems = [ptr::null<LLVMOpaqueMetadata>(); 0];
        let st_size = c.getSize(decl);
        let path_c = decl.path.clone().cstr();
        let name_c = name.clone().cstr();
        let file = LLVMDIBuilderCreateFile(self.builder, path_c.ptr(), path_c.len(), ".".ptr(), 1);
        let flags = 0;
        let st = LLVMDIBuilderCreateStructType(self.builder, self.cu, name_c.ptr(), name_c.len(), file, decl.line, st_size, 0, flags, ptr::null<LLVMOpaqueMetadata>(), elems.ptr(), elems.len() as i32, 0, ptr::null<LLVMOpaqueMetadata>(), name_c.ptr(), name_c.len());
        self.incomplete_types.add(name, st);
        path_c.drop();
        name_c.drop();
        return st;
    }

    func make_variant_type(self, c: Compiler*, decl: Decl*, var_idx: i32, var_part: LLVMOpaqueMetadata*, file: LLVMOpaqueMetadata*, var_size: i64, scope: LLVMOpaqueMetadata*, var_off: i64): LLVMOpaqueMetadata*{
      let ev = decl.get_variants().get(var_idx);
      let name: String = format("{:?}::{}", decl.type, ev.name.str());
      let var_type = c.protos.get().get(&name);
      let elems = List<LLVMOpaqueMetadata*>::new();
      //empty ty
      let name_c = name.clone().cstr();
      let flags=0;
      //fill ty
      //let sl = getStructLayout(var_type);
      let dl = LLVMGetModuleDataLayout(self.ll.module);
      let idx = 0;
      let scp = ptr::null<LLVMOpaqueMetadata>();
      if(decl.base.is_some()){
        let base_ty = self.map_di(decl.base.get(), c);
        let base_size = LLVMDITypeGetSizeInBits(base_ty);
        let off = 0;
        let flagsm = 0;
        let mem = LLVMDIBuilderCreateMemberType(self.builder, scp, base_class_name().ptr(), base_class_name().len(), file, decl.line, base_size, 0, off, flagsm, base_ty);
        elems.add(mem);
        ++idx;
      }
      let fi = 0;
      for fd in &ev.fields{
        let fd_ty = self.map_di(&fd.type, c);
        let off = LLVMOffsetOfElement(dl, var_type, idx);
        let fd_size = LLVMDITypeGetSizeInBits(fd_ty);
        let fdname_c = if (fd.name.is_some()){
          fd.name.get().clone().cstr()
        }else{
          format("_{}", fi).cstr()
        };
        let flagsm = 0;
        let mem = LLVMDIBuilderCreateMemberType(self.builder, scp, fdname_c.ptr(), fdname_c.len(), file, decl.line, fd_size, 0, off, flagsm, fd_ty);
        fdname_c.drop();
        elems.add(mem);
        ++idx;
        ++fi;
      }
      let st = LLVMDIBuilderCreateStructType(self.builder, scope, name_c.ptr(), name_c.len(), file, decl.line, var_size, 0, flags, ptr::null<LLVMOpaqueMetadata>(), elems.ptr(), elems.len() as i32, 0, ptr::null<LLVMOpaqueMetadata>(), name_c.ptr(), name_c.len());
      
      let evname_c = ev.name.clone().cstr();
      let flagsm=0;
      let res = LLVMDIBuilderCreateMemberType(self.builder, var_part, evname_c.ptr(), evname_c.len(), file, decl.line, var_size, 0, var_off, flagsm, st);//var_idx?
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

    func fill_funcs_member(self, decl: Decl*, c: Compiler*, elems: List<LLVMOpaqueMetadata*>*){
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
          elems.add(proto);
        }
      }
    }

    func map_di_fill(self, decl: Decl*, c: Compiler*): LLVMOpaqueMetadata*{
      let s = decl.type.print();
      let st = *self.incomplete_types.get(&s).unwrap();
      let path_c = decl.path.clone().cstr();
      let file = LLVMDIBuilderCreateFile(self.builder, path_c.ptr(),path_c.len(), ".".ptr(), 1);
      path_c.drop();
      let elems = List<LLVMOpaqueMetadata*>::new();
      let base_ty = Option<LLVMOpaqueMetadata*>::new();
      let scope = st;
      if(decl.base.is_some()){
        let ty = self.map_di(decl.base.get(), c);
        base_ty = Option<LLVMOpaqueMetadata*>::new(ty);
      }
      let st_real = c.mapType(&decl.type);
      //let sl = getStructLayout(st_real as StructType*);
      let dl = LLVMGetModuleDataLayout(self.ll.module);
      match decl{
        Decl::Struct(fields)=>{
          let idx = 0;
          if(decl.base.is_some()){
            let ty = *base_ty.get();
            let size = LLVMDITypeGetSizeInBits(ty);
            let off = 0;
            let mem = LLVMDIBuilderCreateMemberType(self.builder, scope, base_class_name().ptr(), base_class_name().len(), file, decl.line, size, 0, off, 0, ty);
            elems.add(mem);
            ++idx;
          }
          let fi = 0;
          for fd in fields{
            let ty = self.map_di(&fd.type, c);
            let size = LLVMDITypeGetSizeInBits(ty);
            let off = LLVMOffsetOfElement(dl, st_real, idx);
            let name_c = if(fd.name.is_some()){
              fd.name.get().clone().cstr()
            }else{
              format("_{}", fi).cstr()
            };
            let mem = LLVMDIBuilderCreateMemberType(self.builder, scope, name_c.ptr(), name_c.len(), file, decl.line, size, 0, off, 0, ty);
            elems.add(mem);
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
            let size = LLVMDITypeGetSizeInBits(ty);
            let off = LLVMOffsetOfElement(dl, st_real, idx);
            let name_c = format("_{}", idx).cstr();
            let mem = LLVMDIBuilderCreateMemberType(self.builder, scope, name_c.ptr(), name_c.len(), file, decl.line, size, 0,  off, 0, ty);
            elems.add(mem);
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
          let fldesc = LLVMDIFlags::LLVMDIFlagArtificial{}.int();
          let disc = LLVMDIBuilderCreateMemberType(self.builder, scope, "".ptr(), 0,  file, decl.line, data_size, 0, tag_off, fldesc, tag);
          let elems2 = List<LLVMOpaqueMetadata*>::new();
          //let var_part = createVariantPart(scope, "".ptr(), file, decl.line, data_size, disc, elems2);
          let var_part = LLVMDIBuilderCreateEnumerationType(self.builder, scope, "".ptr(), 0, file, decl.line, data_size, 0, elems2.ptr(), elems2.len() as i32, st/*? */);/*disc */
          //fill variant
          let var_idx = 1;
          let var_off = LLVMOffsetOfElement(dl, st_real, var_idx);
          for(let i = 0;i < variants.len();++i){
            let ev = variants.get(i);
            let var_type = self.make_variant_type(c, decl, i, var_part, file, data_size, st, var_off);
            elems2.add(var_type);
          }
          //replaceElements(var_part, elems2);
          //LLVMMetadataReplaceAllUsesWith();
          elems.add(var_part);
          elems2.drop();
        },
      }
      //replaceElements(st, elems);
      //LLVMMetadataReplaceAllUsesWith(stold, stnew);
      self.types.add(s, st);
      elems.drop();
      return st;
    }

    func map_di(self, type: Type*, c: Compiler*): LLVMOpaqueMetadata*{
      let rt = c.get_resolver().visit_type(type);
      let name = rt.type.print();
      let res = self.map_di_resolved(&rt.type, &name, c);
      rt.drop();
      name.drop();
      return res;
    }

    func struct_ty(self, name: str, line: i32, size: i32, elems: [LLVMOpaqueMetadata*]): LLVMOpaqueMetadata*{
      let name_c = name.cstr();
      let flags = 0;
      let RunTimeLang = 0;
      let res = LLVMDIBuilderCreateStructType(self.builder, self.cu, name_c.ptr(), name_c.len(), self.file, line, size, 0, flags, ptr::null<LLVMOpaqueMetadata>(), elems.ptr(), elems.len() as i32, RunTimeLang, ptr::null<LLVMOpaqueMetadata>(), name_c.ptr(), name_c.len());
      name_c.drop();
      return res;
    }

    func map_di_resolved(self, type: Type*, name: String*, c: Compiler*): LLVMOpaqueMetadata*{
      let opt1 = self.types.get(name);
      if(opt1.is_some()){
        return *opt1.unwrap();
      }
      let opt2 = self.incomplete_types.get(name);
      if(opt2.is_some()){
        return *opt2.unwrap();
      }
      match type{
        Type::Pointer(elem) => {
          let nameptr = "";
          return LLVMDIBuilderCreatePointerType(self.builder, self.map_di(elem.get(), c), 64, 0, 0, nameptr.ptr(), nameptr.len());
        },
        Type::Array(elem, count)=>{
          let elems = [LLVMDIBuilderGetOrCreateSubrange(self.builder, 0, *count)];
          let elem_ty = self.map_di(elem.get(), c);
          let size = c.getSize(type);
          let align = 0;
          let res = LLVMDIBuilderCreateArrayType(self.builder, size, align, elem_ty, elems.ptr(), elems.len() as i32);
          return res;
        },
        Type::Function(ft_box)=>{
          let tys = List<LLVMOpaqueMetadata*>::new();
          tys.add(self.map_di(&ft_box.get().return_type, c));
          for prm in & ft_box.get().params{
            tys.add(self.map_di(prm, c));
          }
          let file = self.file;
          let spt = LLVMDIBuilderCreateSubroutineType(self.builder, file, tys.ptr(), tys.len() as i32, LLVMDIFlags::LLVMDIFlagZero{}.int());
          let nameptr = "";
          tys.drop();
          return LLVMDIBuilderCreatePointerType(self.builder, spt, 64, 0, 0, nameptr.ptr(), nameptr.len());
        },
        Type::Lambda(ft_box) => {
          let tys = List<LLVMOpaqueMetadata*>::new();
          tys.add(self.map_di(ft_box.get().return_type.get(), c));
          for prm in & ft_box.get().params{
            tys.add(self.map_di(prm, c));
          }
          for prm in & ft_box.get().captured{
            tys.add(self.map_di(prm, c));
          }
          let spt = LLVMDIBuilderCreateSubroutineType(self.builder, self.file, tys.ptr(), tys.len() as i32, LLVMDIFlags::LLVMDIFlagZero{}.int());
          tys.drop();
          let nameptr = "";
          return LLVMDIBuilderCreatePointerType(self.builder, spt, 64, 0, 0, nameptr.ptr(), nameptr.len());
        },
        Type::Slice(elem)=>{
          let nameptr = "";
          let size = c.getSize(type);
          let line = 0;
          //ptr
          let ptr_ty = LLVMDIBuilderCreatePointerType(self.builder, self.map_di(elem.get(), c), 64, 0, 0, nameptr.ptr(), nameptr.len());
          let off = 0;
          let flags = 0;
          let ptr_mem = LLVMDIBuilderCreateMemberType(self.builder, ptr::null<LLVMOpaqueMetadata>(), "ptr".ptr(), 3, self.file, line, 64, 0, off, flags, ptr_ty);
          //len
          let bits: Type = as_type(SLICE_LEN_BITS());
          let len_ty = self.map_di(&bits, c);
          bits.drop();
          let len_mem = LLVMDIBuilderCreateMemberType(self.builder, ptr::null<LLVMOpaqueMetadata>(), "len".ptr(), 3, self.file, line, SLICE_LEN_BITS(), 0, 64, flags, len_ty);
          let name_c = "_slice".cstr();
          let elems = [ptr_mem, len_mem];
          let flags2 = 0;
          let RunTimeLang = 0;
          let res = LLVMDIBuilderCreateStructType(self.builder, self.cu, name_c.ptr(), name_c.len(), self.file, line, size, 0, flags2, ptr::null<LLVMOpaqueMetadata>(), elems.ptr(), elems.len() as i32, RunTimeLang, ptr::null<LLVMOpaqueMetadata>(), name_c.ptr(), name_c.len());
          name_c.drop();
          return res;
        },
        Type::Tuple(tt) => {
          let name_c = mangleType(type).cstr();
          let line = 0;
          let size = c.getSize(type);
          let elems = List<LLVMOpaqueMetadata*>:: new();
          let idx = 0;
          let ty = c.mapType(type) ;
          let dl = LLVMGetModuleDataLayout(self.ll.module);
          for elem in &tt.types{
            let elem_di = self.map_di(elem, c);
            let off = LLVMOffsetOfElement(dl, ty, idx);
            let flags2 = 0;
            let elem_name = format("_{}", idx).cstr();
            let mem = LLVMDIBuilderCreateMemberType(self.builder, ptr::null<LLVMOpaqueMetadata>(), elem_name.ptr(), elem_name.len(), self.file, line, size, 0, off, flags2, elem_di);
            elems.add(mem);
            ++idx;
            elem_name.drop();
          }
          let res = LLVMDIBuilderCreateStructType(self.builder, self.cu, name_c.ptr(), name_c.len(), self.file, line, size, 0, 0, ptr::null<LLVMOpaqueMetadata>(), elems.ptr(), elems.len() as i32, 0, ptr::null<LLVMOpaqueMetadata>(), name_c.ptr(), name_c.len());
          name_c.drop();
          elems.drop();
          return res;
        },
        Type::Simple(smp)=>{
          if(name.eq("void")) return ptr::null<LLVMOpaqueMetadata>();
          if(name.eq("bool")){
            return self.createBasicType(name, 8, LLVMDWARFTypeEncoding_Boolean);
          }
          if(name.eq("i8") || name.eq("i16") || name.eq("i32") || name.eq("i64")){
            let size = c.getSize(type);
            return self.createBasicType(name, size, LLVMDWARFTypeEncoding_Signed);
          }
          if(name.eq("u8") || name.eq("u16") || name.eq("u32") || name.eq("u64")){
            let size = c.getSize(type);
            return self.createBasicType(name, size, LLVMDWARFTypeEncoding_Unsigned);
          }
          if(name.eq("f32") || name.eq("f64")){
            let size = c.getSize(type);
            return self.createBasicType(name, size, LLVMDWARFTypeEncoding_Float);
          }
          //already mapped
          panic("map di {}\n", name);
        }
      }
    }

    func createBasicType(self, name: String*, size: i64, enc: i32): LLVMOpaqueMetadata*{
      let name_c = name.clone().cstr();
      let flags = LLVMDIFlags::LLVMDIFlagZero{}.int();
      let res = LLVMDIBuilderCreateBasicType(self.builder, name_c.ptr(), name.len(), size, enc, flags);
      name_c.drop();
      return res;
    }
}
