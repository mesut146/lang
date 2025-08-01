import std/map
import std/libc
import std/stack

import ast/ast
import ast/printer
import ast/utils

import resolver/resolver

import parser/llvm
import parser/compiler
import parser/debug_helper
import parser/expr_emitter
import parser/ownership
import parser/own_model

const POINTER_SIZE: i32 = 64;

struct RvalueHelper {
  rvalue: bool;
  scope: Option<Expr*>;
  scope_type: Option<Type>;
}

impl RvalueHelper{
    func is_rvalue(e: Expr*): bool{
      if let Expr::Par(inner) = e{
        return is_rvalue(inner.get());
      }
      if let Expr::Unary(op, inner) = e{
        if(op.eq("*")){
          return true;
        }
      }
      return e is Expr::Call || e is Expr::Lit || e is Expr::As || e is Expr::Infix;
    }

    func get_scope(mc: Call*): Expr*{
      if (mc.is_static) {
        return mc.args.get(0);
      } else {
        return mc.scope.get();
      }
    }

    func need_alloc(mc: Call*, method: Method*, r: Resolver*): RvalueHelper{
      let res = RvalueHelper{false, Option<Expr*>::new(), Option<Type>::new()};
       if(method.self.is_none() || (mc.is_static && mc.args.empty())){
         return res;
       }
       let scp = get_scope(mc);
       res.scope = Option::new(scp);
       if(method.self.get().type.is_pointer()){
         let scope_type = r.visit(scp);
         if (scope_type.type.is_prim() && is_rvalue(scp)) {
            res.rvalue = true;
            res.scope_type = Option::new(scope_type.type.clone());
         }
         scope_type.drop();
       }
       return res;
    }
}


func make_slice_type(ll: Emitter*): LLVMOpaqueType*{
    let res = LLVMStructCreateNamed(ll.ctx, "__slice".ptr());
    let elems = [LLVMPointerType(LLVMIntTypeInContext(ll.ctx, 8), 0), LLVMIntTypeInContext(ll.ctx, SLICE_LEN_BITS())];
    LLVMStructSetBody(res, elems.ptr(), 2, 0);
    return res;
}

func make_printf(ll: Emitter*): FunctionInfo{
    let args = [LLVMPointerType(LLVMIntTypeInContext(ll.ctx, 8), 0)];
    let ret = LLVMIntTypeInContext(ll.ctx, 32);
    let ft = LLVMFunctionType(ret, args.ptr(), 1, LLVMBoolTrue());
    let f = LLVMAddFunction(ll.module, "printf".ptr(), ft);
    LLVMSetFunctionCallConv(f, 0);
    return FunctionInfo{f, ft};
}
func make_sprintf(ll: Emitter*): FunctionInfo{
  let args = [LLVMPointerType(LLVMIntTypeInContext(ll.ctx, 8), 0), LLVMPointerType(LLVMIntTypeInContext(ll.ctx, 8), 0)];
  let ret = LLVMIntTypeInContext(ll.ctx, 32);
  let ft = LLVMFunctionType(ret, args.ptr(), 2, LLVMBoolTrue());
  let f = LLVMAddFunction(ll.module, "sprintf".ptr(), ft);
  LLVMSetFunctionCallConv(f, 0);
  return FunctionInfo{f, ft};
}
func make_fflush(ll: Emitter*): FunctionInfo{
  let args = [LLVMPointerType(LLVMIntTypeInContext(ll.ctx, 8), 0)];
  let ret = LLVMIntTypeInContext(ll.ctx, 32);
  let ft = LLVMFunctionType(ret, args.ptr(), 1, LLVMBoolFalse());
  let f = LLVMAddFunction(ll.module, "fflush".ptr(), ft);
  LLVMSetFunctionCallConv(f, 0);
  return FunctionInfo{f, ft};
}
func make_malloc(ll: Emitter*): FunctionInfo{
  let args = [LLVMIntTypeInContext(ll.ctx, 64)];
  let ret = LLVMPointerType(LLVMIntTypeInContext(ll.ctx, 8), 0);
  let ft = LLVMFunctionType(ret, args.ptr(), 1, LLVMBoolFalse());
  let f = LLVMAddFunction(ll.module, "malloc".ptr(), ft);
  LLVMSetFunctionCallConv(f, 0);
  return FunctionInfo{f, ft};
}

func getTypes(items: List<Item>*, list: List<Decl*>*){
    for (let i = 0;i < items.len();++i) {
        let item = items.get(i);
        match item{
          Item::Decl(d)=>{
              if(d.is_generic) continue;
              list.add(d);
          },
          Item::Module(md)=>{
              getTypes(&md.items, list);
          },
          _=>{}
        }
    }
}

func sort(list: List<Decl*>*, r: Resolver*){
  for (let i = 0; i < list.len(); ++i) {
    //find decl belongs to i'th index
    let min: Decl* = *list.get(i);
    for (let j = i + 1; j < list.len(); ++j) {
      let cur: Decl* = *list.get(j);
      if (r.is_cyclic(&min.type, &cur.type)) {
        min = cur;
        swap(list, i, j);
      }
    }
  }
}

func all_deps(type: Type*, r: Resolver*, arr: List<String>*){
  if(type.is_any_pointer() || type.is_prim() || type.is_slice()) return;
  if(type.is_array()){
    all_deps(type.elem(), r, arr);
    return;
  }
  let rt = r.visit_type(type);
  let opt = r.get_decl(&rt);
  if(opt.is_none()){
    rt.drop();
    return;
  }
  arr.add_not_exist(type.print());
  let decl = opt.unwrap();
  all_deps(decl, r, arr);
  rt.drop();
}

func all_deps(decl: Decl*, r: Resolver*, res: List<String>*){
  if(decl.base.is_some()){
    all_deps(decl.base.get(), r, res);
  }
  match decl{
    Decl::Struct(fields)=>{
      for (let j = 0; j < fields.len(); ++j) {
        let fd = fields.get(j);
        //add_type(res, &fd.type);
        all_deps(&fd.type, r, res);
      }
    },
    Decl::Enum(variants)=>{
      for (let j = 0; j < variants.len(); ++j) {
        let ev = variants.get(j);
        for (let k = 0; k < ev.fields.len(); ++k) {
          let fd = ev.fields.get(k);
          //add_type(res, &fd.type);
          all_deps(&fd.type, r, res);
        }
      }
    },
    Decl::TupleStruct(fields)=>{
      for fd in fields{
        //add_type(res, &ft);
        all_deps(&fd.type, r, res);
      }
    }
  }
}

func sort4(list: List<Decl*>*, r: Resolver*){
  let index_map = Map<String, i32>::new(list.len());
  for (let i = 0; i < list.len(); ++i) {
    let d: Decl* = *list.get(i);
    index_map.add(d.type.print(), 0);
    if(d is Decl::Struct){
      let fields = d.get_fields();
      for (let j = 0; j < fields.len(); ++j) {
        let fd = fields.get(j);
        let key = fd.type.print();
      }
    }
  }
}

func sort2(list: List<Decl*>*, r: Resolver*){
  //parent -> fields
  let map = Map<String, List<String>>::new();
  //field -> parents
  //let map2 = Map<String, List<String>>::new();
  for (let i = 0; i < list.len(); ++i) {
    let decl = *list.get(i);
    let arr = List<String>::new();
    all_deps(decl, r, &arr);
    /*for ch in &arr{
      let parents = &map2.get_pair_or(ch.clone(), List<String>::new()).b;
      parents.add_not_exist(decl.type.print());
    }*/
    //print("{} -> {}\n", decl.type, arr);
    map.add(decl.type.print(), arr);
  }
  //print("map2={}\n", map2);
  //sort
  //let left_all = List<String>::new();
  let right_all = List<String>::new();
  for (let j = 0; j < list.len(); ++j) {
    let d: Decl* = *list.get(j);
    right_all.add(d.type.print());
  }
  for (let i = 0; i < list.len() - 1; ++i) {
    //find decl for i
    //i place, have all fields on left, all parents on right
    for (let j = i + 1; j < list.len(); ++j) {
      let d2: Decl* = *list.get(j);
      let s2 = d2.type.print();
      let fields: List<String>* = map.get(&s2).unwrap();
      //let parents: List<String>* = map2.get(&s2).unwrap();
      let is_all_left = true;
      let is_all_right = true;
      for fd in fields{
        if(right_all.contains(fd)){
          is_all_left = false;
          break;
        }
      }
      if(is_all_left){
        //j belongs to i
        let rpos = right_all.indexOf(&s2);
        right_all.remove(rpos).drop();
        swap(list, i, j);
        break;
      }
      s2.drop();
    }
  }
  //print("sorted={}\n", list);
  map.drop();
  right_all.drop();
}

func printlist(list: List<Decl*>*){
  print("list={\n");
  for (let i = 0; i < list.len(); ++i) {
    let decl = *list.get(i);
    print("  {:?}", decl.type);
  }
  print("}\n\n");
}

func swap(list: List<Decl*>*, i: i32, j: i32){
  let a = *list.get(i);
  let b = *list.get(j);
  list.set(j, a);
  list.set(i, b);
}

func getMethods(unit: Unit*): List<Method*>{
  let list = List<Method*>::new();
  getMethods(&unit.items, &list);
  return list;
}

func getMethods(items: List<Item>*, list: List<Method*>*){
  for item in items{
    match item{
      Item::Method(m)=>{
          if(m.is_generic) continue;
          list.add(m);
      },
      Item::Impl(imp)=>{
        if(!imp.info.type_params.empty()) continue;
        for(let j = 0;j < imp.methods.len();++j){
          list.add(imp.methods.get(j));
        }
      },
      Item::Extern(items2)=>{
        for ei in items2{
          if let ExternItem::Method(m)=ei{
            list.add(m);
          }
        }
      },
      Item::Module(md) => {
        //todo
        getMethods(&md.items, list);
      },
      _ => {}
    }
  }
}

impl Compiler{
  func get_global_string(self, val: String): LLVMOpaqueValue*{
    let opt = self.string_map.get(&val);
    if(opt.is_some()){
      val.drop();
      return *opt.unwrap();
    }
    let val2 = val.clone();
    let val_c = val.cstr();
    let ptr = self.ll.get().glob_str(val2.str());
    self.string_map.add(val2, ptr);
    val_c.drop();
    return ptr;
  }
  func make_proto(self, ft: FunctionType*): LLVMOpaqueType*{
    let ret = self.mapType(&ft.return_type);
    let args = List<LLVMOpaqueType*>::new();
    for prm in &ft.params{
      args.add(self.mapType(prm));
    }
    let res = LLVMFunctionType(ret, args.ptr(), ft.params.len() as i32, LLVMBoolFalse());
    args.drop();
    return res;
  }
  func make_proto(self, ft: LambdaType*): LLVMOpaqueType*{
    let ret = self.mapType(ft.return_type.get());
    let args = List<LLVMOpaqueType*>::new();
    for prm in &ft.params{
      args.add(self.mapType(prm));
    }
    for prm in &ft.captured{
      args.add(self.mapType(prm));
    }
    let res = LLVMFunctionType(ret, args.ptr(), args.len() as i32, LLVMBoolFalse());
    args.drop();
    return res;
  }
  func mapType(self, type: Type*): LLVMOpaqueType*{
    let r = self.get_resolver();
    let rt = r.visit_type(type);
    let str = rt.type.print();
    let res = self.mapType2(&rt);
    rt.drop();
    str.drop();
    return res;
  }

  func mapType2(self, rt: RType*): LLVMOpaqueType*{
    let ll = self.ll.get();
    let type = &rt.type;
    match type{
      Type::Pointer(elem) =>{
        let elem_ty = self.mapType(elem.get());
        return LLVMPointerType(elem_ty, 0);
      },
      Type::Array(elem, size) =>{
        let elem_ty = self.mapType(elem.get());
        return LLVMArrayType(elem_ty, *size as u32);
      },
      Type::Slice(elem) =>{
        let p = self.protos.get();
        return p.std("slice") as LLVMOpaqueType*;
      },
      Type::Function(elem_bx)=>{
        let res = self.make_proto(elem_bx.get());
        return LLVMPointerType(res as LLVMOpaqueType*, 0);
      },
      Type::Lambda(elem_bx)=>{
        let res = self.make_proto(elem_bx.get());
        return LLVMPointerType(res as LLVMOpaqueType*, 0);
      },
      Type::Tuple(tt)=>{
        let name = mangleType(type).cstr();
        let p = self.protos.get();
        let opt = p.classMap.get_str(name.str());
        if(opt.is_some()){
          let res = *opt.unwrap();
          name.drop();
          return res as LLVMOpaqueType*;
        }
        let res = ll.make_struct_ty(name.str());
        let elems = List<LLVMOpaqueType*>::new(tt.types.len());
        for elem in &tt.types{
          elems.add(self.mapType(elem));
        }
        LLVMStructSetBody(res, elems.ptr(), elems.len() as i32, 0);
        p.classMap.add(name.str().owned(), res);
        name.drop();
        return res;
      },
      Type::Simple(smp) => {
        if(type.is_void()) return LLVMVoidTypeInContext(ll.ctx);
        if(type.eq("f32")) return LLVMFloatTypeInContext(ll.ctx);
        if(type.eq("f64")) return LLVMDoubleTypeInContext(ll.ctx);
        let prim_size = prim_size(smp.name.str());
        if(prim_size.is_some()){
          return LLVMIntTypeInContext(ll.ctx, prim_size.unwrap());
        }
        let decl = self.get_resolver().get_decl(rt).unwrap();
        if(decl.is_repr()){
          let at = decl.attr.find("repr").unwrap().args.get(0).print();
          let ty = Type::new(at);
          let res = self.mapType(&ty);
          ty.drop();
          return res;
        }
        
        let p = self.protos.get();
        let s = type.print();
        if(!p.classMap.contains(&s)){
          panic("mapType2 {}\n", s);
        }
        let res = p.get(&s);
        s.drop();
        return res as LLVMOpaqueType*;
      }
    }
  }

  //normal decl protos and di protos
  func make_decl_protos(self){
    let p = self.protos.get();
    let resolver = self.get_resolver();
    let list = List<Decl*>::new();
    getTypes(&self.unit().items, &list);
    //print("used={}\n", resolver.used_types);
    for rt in &resolver.used_types{
      let decl = resolver.get_decl(rt).unwrap();
      if (decl.is_generic) continue;
      list.add(decl);
    }
    sort2(&list, resolver);
    //first create just protos to fill later
    for(let i = 0;i < list.len();++i){
      let decl = *list.get(i);
      //print("decl proto {}\n", decl.type);
      self.make_decl_proto(decl);
    }
    //fill with elems
    for(let i = 0;i < list.len();++i){
      let decl = *list.get(i);
      self.fill_decl(decl, p.get(decl));
    }
    if(self.di.get().debug){
      //di proto
      for(let i = 0;i < list.len();++i){
        let decl = *list.get(i);
        self.di.get().map_di_proto(decl, self);
      }
      //di fill
      for(let i = 0;i < list.len();++i){
        let decl = *list.get(i);
        self.di.get().map_di_fill(decl, self);
      }
    }
    list.drop();
  }

  func make_decl_proto(self, decl: Decl*){
    let p = self.protos.get();
    let ll = self.ll.get();
    if(decl.is_enum()){
      let vars = decl.get_variants();
      for(let i = 0;i < vars.len();++i){
        let ev = vars.get(i);
        let name = format("{:?}::{}", decl.type, ev.name);
        let name_c = name.clone().cstr();
        //let var_ty = make_struct_ty(name_c.ptr());
        let var_ty = LLVMStructCreateNamed(ll.ctx,name_c.ptr());
        name_c.drop();
        p.classMap.add(name, var_ty);
      }
    }
    let type_c = decl.type.print().cstr();
    //let st = make_struct_ty(type_c.ptr());
    let st = LLVMStructCreateNamed(ll.ctx, type_c.ptr());
    type_c.drop();
    p.classMap.add(decl.type.print(), st);
  }

  func fill_decl(self, decl: Decl*, st: LLVMOpaqueType*){
    let p = self.protos.get();
    let ll = self.ll.get();
    let elems = List<LLVMOpaqueType*>::new();
    match decl{
      Decl::Enum(variants)=>{
        //calc enum size
        let max = 0;
        for(let i = 0;i < variants.len();++i){
          let ev = variants.get(i);
          let name = format("{:?}::{}", decl.type, ev.name.str());
          let var_ty = p.get(&name);
          self.make_variant_type(ev, decl, &name, var_ty);
          let variant_size = ll.sizeOf(var_ty);
          if(variant_size > max){
            max = variant_size as i32;
          }
          name.drop();
        }
        elems.add(ll.intTy(ENUM_TAG_BITS()));
        elems.add(LLVMArrayType(ll.intTy(8), max/8));
      },
      Decl::Struct(fields)=>{
        if(decl.base.is_some()){
          elems.add(self.mapType(decl.base.get()));
        }
        for(let i = 0;i < fields.len();++i){
          let fd = fields.get(i);
          let ft = self.mapType(&fd.type);
          elems.add(ft);
        }
      },
      Decl::TupleStruct(fields)=>{
        //todo base
        for fd in fields{
          let ft2 = self.mapType(&fd.type);
          elems.add(ft2);
        }
      }
    }
    LLVMStructSetBody(st, elems.ptr(), elems.len() as i32, 0);
    elems.drop();
  }
  func make_variant_type(self, ev: Variant*, decl: Decl*, name: String*, ty: LLVMOpaqueType*){
    let elems = List<LLVMOpaqueType*>::new();
    if(decl.base.is_some()){
      elems.add(self.mapType(decl.base.get()));
    }
    for(let j = 0;j < ev.fields.len();++j){
      let fd = ev.fields.get(j);
      let ft = self.mapType(&fd.type);
      elems.add(ft);
    }
    LLVMStructSetBody(ty, elems.ptr(), elems.len() as i32, 0);
    elems.drop();
  }

  func make_proto(self, m: Method*): Option<FunctionInfo>{
    let ll = self.ll.get();
    if(m.is_generic) return Option<FunctionInfo>::new();
    let mangled = mangle(m);
    //print("proto {}\n", mangled);
    if(self.protos.get().funcMap.contains(&mangled)){
      panic("already proto {}\n", mangled);
    }
    let sig = MethodSig::new(m, self.get_resolver());
    let rvo = is_struct(&sig.ret);
    let ret = LLVMVoidTypeInContext(ll.ctx);
    if(is_main(m)){
      ret = ll.intTy(32);
    }else if(!rvo){
      ret = self.mapType(&sig.ret);
    }
    let args = List<LLVMOpaqueType*>::new();
    if(rvo){
      let rvo_ty = LLVMPointerType(self.mapType(&sig.ret), 0);
      args.add(rvo_ty);
    }
    for prm_type in &sig.params{
      let pt = self.mapType(prm_type);
      if(is_struct(prm_type)){
        args.add(LLVMPointerType(pt, 0));
      }else{
        args.add(pt);
      }
    }
    let ft = LLVMFunctionType(ret, args.ptr(), args.len() as i32, toLLVMBool(m.is_vararg));
    let linkage = LLVMLinkage::LLVMExternalLinkage;
    if(!m.type_params.empty()){
      linkage = LLVMLinkage::LLVMLinkOnceODRLinkage;
    }else if let Parent::Impl(info)=&m.parent{
      if(info.type.is_simple() && !info.type.get_args().empty()){
        linkage = LLVMLinkage::LLVMLinkOnceODRLinkage;
      }
    }
    let mangled_c = mangled.clone().cstr();
    let f = LLVMAddFunction(ll.module, mangled_c.ptr(), ft);
    LLVMSetLinkage(f, linkage.int());
    if(rvo){
      let arg = LLVMGetParam(f, 0);
      LLVMSetValueName2(arg, "_ret".ptr(), 3);
      //Argument_setsret(arg, self.mapType(&sig.ret));
      let kind= LLVMGetEnumAttributeKindForName("sret".ptr(), 4);
      let attr = LLVMCreateTypeAttribute(ll.ctx, kind, self.mapType(&sig.ret));
      LLVMAddAttributeAtIndex(f, 1, attr);
    }
    self.protos.get().funcMap.add(mangled, FunctionInfo{f, ft});
    args.drop();
    mangled_c.drop();
    sig.drop();
    return Option::new(FunctionInfo{f, ft});
  }
  
  // func make_proto2(self, m: Method*): Option<FunctionInfo>{
  //   if(m.is_generic) return Option<FunctionInfo>::new();
  //   let mangled = mangle(m);
  //   //print("proto {}\n", mangled);
  //   if(self.protos.get().funcMap.contains(&mangled)){
  //     panic("already proto {}\n", mangled);
  //   }
  //   let ll = self.ll.get();
  //   let sig = MethodSig::new(m, self.get_resolver());
  //   let rvo = is_struct(&m.type);
  //   let ret = LLVMVoidTypeInContext(ll.ctx);
  //   if(is_main(m)){
  //     ret = LLVMIntTypeInContext(ll.ctx, 32);
  //   }else if(!rvo){
  //     ret = self.mapType(&sig.ret);
  //   }
  //   let args = List<LLVMOpaqueType*>::new();
  //   if(rvo){
  //     let rvo_ty = LLVMPointerType(self.mapType(&sig.ret), 0);
  //     args.add(rvo_ty);
  //   }
  //   for prm_type in &sig.params{
  //     let pt = self.mapType(prm_type);
  //     if(is_struct(prm_type)){
  //       args.add(LLVMPointerType(pt, 0));
  //     }else{
  //       args.add(pt);
  //     }
  //   }
  //   let ft = LLVMFunctionType(ret, args.ptr(), args.len() as i32, toLLVMBool(m.is_vararg));
  //   let linkage = LLVMLinkage::LLVMExternalLinkage{}.int();
  //   if(!m.type_params.empty()){
  //     linkage = LLVMLinkage::LLVMLinkOnceODRLinkage{}.int();
  //   }else if let Parent::Impl(info)=&m.parent{
  //     if(info.type.is_simple() && !info.type.get_args().empty()){
  //       linkage = LLVMLinkage::LLVMLinkOnceODRLinkage{}.int();
  //     }
  //   }
  //   let mangled_c = mangled.clone().cstr();
  //   let f = LLVMAddFunction(ll.module, mangled_c.ptr(), ft);
  //   LLVMSetLinkage(f, linkage);
  //   if(rvo){
  //     let arg = LLVMGetParam(f, 0);
  //     LLVMSetValueName2(arg, "ret".ptr(), 3);
  //     let sret = LLVMGetEnumAttributeKindForName("sret".ptr(), 4);
  //     let attr = LLVMCreateTypeAttribute(ll.ctx, sret, self.mapType(&sig.ret));
  //     LLVMAddAttributeAtIndex(f, 1, attr);
  //   }
  //   self.protos.get().funcMap.add(mangled, FunctionInfo{f, ft});
  //   args.drop();
  //   mangled_c.drop();
  //   sig.drop();
  //   return Option::new(FunctionInfo{f, ft});
  // }

  func getSize(self, type: Type*): i64{
    let ll = self.ll.get();
    match type{
      Type::Pointer(bx) => return POINTER_SIZE,
      Type::Function(bx) => return POINTER_SIZE,
      Type::Lambda(bx) => return POINTER_SIZE,
      Type::Slice(bx) => {
        let st = self.protos.get().std("slice");
        return ll.sizeOf(st);
        //return self.ll.get().sizeOf(st as LLVMOpaqueType*);
      },
      Type::Array(elem, size) => {
        return self.getSize(elem.get()) * (*size);
      },
      Type::Tuple(tt) => {
        let rt = self.get_resolver().visit_type(type);
        let mapped = self.mapType(&rt.type);
        rt.drop();
        return ll.sizeOf(mapped);
      },
      Type::Simple(smp) => {
        if(type.is_prim()){
          return prim_size(type.name().str()).unwrap();
        }
        let rt = self.get_resolver().visit_type(type);
        if(rt.is_decl()){
          let decl = self.get_resolver().get_decl(&rt).unwrap();
          rt.drop();
          return self.getSize(decl);
        }
        rt.drop();
        panic("no decl");
      }
    }
  }

  func getSize(self, decl: Decl*): i64{
    let mapped = self.mapType(&decl.type);
    return self.ll.get().sizeOf(mapped);
  }

  func cast(self, expr: Expr*, target_type: Type*): LLVMOpaqueValue*{
    let ll = self.ll.get();
    let src_type = self.get_resolver().getType(expr);
    let val = self.loadPrim(expr);
    let is_unsigned = isUnsigned(&src_type);
    let target_ty = self.mapType(target_type);

    if(target_type.is_float()){
      if(src_type.is_float()){
        if(src_type.eq("f32")){
          //f32 -> f64
          src_type.drop();
          return LLVMBuildFPExt(ll.builder, val, target_ty, "".ptr());
        }else{
          //f64 -> f32
          src_type.drop();
          return LLVMBuildFPTrunc(ll.builder, val, target_ty, "".ptr());
        }
      }else{
        if(is_unsigned){
          src_type.drop();
          return LLVMBuildUIToFP(ll.builder, val, target_ty, "".ptr());
        }else{
          src_type.drop();
          return LLVMBuildSIToFP(ll.builder, val, target_ty, "".ptr());
        }
      }
    }
    if(src_type.is_float()){
      if(is_unsigned){
        src_type.drop();
        return LLVMBuildFPToUI(ll.builder, val, target_ty, "".ptr());
      }else{
        src_type.drop();
        return LLVMBuildFPToSI(ll.builder, val, target_ty, "".ptr());
      }
    }
    let val_ty = LLVMTypeOf(val);
    let src_size = ll.sizeOf(val_ty);
    let trg_size = self.getSize(target_type);
    let trg_ty = ll.intTy(trg_size as i32);
    if(src_size < trg_size){
      if(is_unsigned){
        src_type.drop();
        return LLVMBuildZExt(ll.builder, val, trg_ty, "".ptr());
      }else{
        src_type.drop();
        return LLVMBuildSExt(ll.builder, val, trg_ty, "".ptr());
      }
    }else if(src_size > trg_size){
      src_type.drop();
      return LLVMBuildTrunc(ll.builder, val, trg_ty, "".ptr());
    }
    src_type.drop();
    return val;
  }
  
  func cast2(self, val: LLVMOpaqueValue*, src_type: Type*, target_type: Type*): LLVMOpaqueValue*{
    let is_unsigned = isUnsigned(src_type);
    let ll = self.ll.get();
    let val_ty = LLVMTypeOf(val);
    let src_size = ll.sizeOf(val_ty);
    let trg_size = self.getSize(target_type);
    let trg_ty = ll.intTy(trg_size as i32);
    if(src_size < trg_size){
      if(is_unsigned){
        return LLVMBuildZExt(ll.builder, val, trg_ty, "".ptr());
      }else{
        return LLVMBuildSExt(ll.builder, val, trg_ty, "".ptr());
      }
    }else if(src_size > trg_size){
      return LLVMBuildTrunc(ll.builder, val, trg_ty, "".ptr());
    }
    return val;
  }

  func loadPrim(self, expr: Expr*): LLVMOpaqueValue*{
    let val = self.visit(expr);
    let ll = self.ll.get();
    let ty = LLVMTypeOf(val);
    if(!Emitter::isPtr(ty)) return val;
    let type = self.getType(expr);
    assert(is_loadable(&type));
    let res = LLVMBuildLoad2(ll.builder, self.mapType(&type), val, "".ptr());//local var
    type.drop();
    return res;
  }

  func loadPrim(self, val: LLVMOpaqueValue*, type: Type*): LLVMOpaqueValue*{
    assert(is_loadable(type));
    let ll = self.ll.get();
    let ty = LLVMTypeOf(val);
    if(!Emitter::isPtr(ty)) return val;
    let res = LLVMBuildLoad2(ll.builder, self.mapType(type), val, "".ptr());//local var
    return res;
  }

  func setField(self, expr: Expr*, type: Type*, trg: LLVMOpaqueValue*){
    self.setField(expr, type, trg, Option<Expr*>::new());
  }
  func setField(self, expr: Expr*, type: Type*, trg: LLVMOpaqueValue*, lhs: Option<Expr*>){
      let rt = self.get_resolver().visit_type(type);
      self.setField(expr, &rt, trg, lhs);
      rt.drop();
  }
  func setField(self, expr: Expr*, rt: RType*, trg: LLVMOpaqueValue*, lhs: Option<Expr*>){
      let type = &rt.type;
      let ll = self.ll.get();
      if(is_struct(type)){
        if(can_inline(expr, self.get_resolver())){
          //todo own drop_lhs
          self.do_inline(expr, trg);
          return;
        }
        let val = self.visit(expr);
        if(lhs.is_some()){
          self.own.get().drop_lhs(lhs.unwrap(), trg);
        }
        self.copy(trg, val, type);
      }else if(type.is_any_pointer()){
        let val = self.get_obj_ptr(expr);
        LLVMBuildStore(ll.builder, val, trg);
      }else{
        let val = self.cast(expr, type);
        LLVMBuildStore(ll.builder, val, trg); 
      }
  }

  //returns 1 bit for br
  func branch(self, expr: Expr*): LLVMOpaqueValue*{
    let val = self.loadPrim(expr);
    let ll = self.ll.get();
    return LLVMBuildTrunc(ll.builder, val, ll.intTy(1), "".ptr());
  }
  //returns 1 bit for br
  func branch(self, val: LLVMOpaqueValue*): LLVMOpaqueValue*{
    let ll = self.ll.get();
    return LLVMBuildTrunc(ll.builder, val, ll.intTy(1), "".ptr());
  }

  func load(self, val: LLVMOpaqueValue*, ty: Type*): LLVMOpaqueValue*{
    let mapped = self.mapType(ty);
    let ll = self.ll.get();
    return LLVMBuildLoad2(ll.builder, mapped, val, "".ptr());
  }

  func emit_as_arg(self, node: Expr*): LLVMOpaqueValue*{
    let ty = self.getType(node);
    if(ty.is_prim()){
      let val = self.visit(node);
      let res = self.load(val,  &ty);
      ty.drop();
      return res;
    }
    match node{
      Lit(val) => return self.visit(node),
      Name(val)=>{
        //todo
        return self.visit(node);
      },
      Call(mc) => return self.visit(node),
      MacroCall(mc) => return self.visit(node),
      Par(e) => return self.visit(node),
      Type(val) => return self.visit(node),
      Unary(op, e) => return self.visit(node),
      Infix(op, l, r) => return self.visit(node),
      Access(scope, name) => {
        //todo
        // loadprim
        return self.visit(node);
      },
      Obj(type, args) => return self.visit(node),
      As(e, type) => return self.visit(node),
      Is(e, rhs) => return self.visit(node),
      Array(list, size) => return self.visit(node),
      ArrAccess(val) => return self.visit(node),
      Match(val) => return self.visit(node),
      Block(x) => return self.visit(node),
      If(is) => return self.visit(node),
      IfLet(il) => return self.visit(node),
      Lambda(val) => return self.visit(node),
      Ques(e) => return self.visit(node),
      Tuple(elems) => return self.visit(node),
    }
  }

  func get_obj_ptr(self, node: Expr*): LLVMOpaqueValue*{
    if let Expr::Par(e)=node{
      return self.get_obj_ptr(e.get());
    }
    if let Expr::Unary(op, e)=node{
      if(op.eq("*")){
        return self.visit(node);
      }
    }
    let val = self.visit(node);
    if(node is Expr::Obj || node is Expr::Call || node is Expr::MacroCall || node is Expr::Lit || node is Expr::Unary || node is Expr::As || node is Expr::Infix){
      return val;
    }
    if(node is Expr::Name || node is Expr::ArrAccess || node is Expr::Access){
      let ty = self.get_resolver().visit(node);
      if(ty.type.is_any_pointer() && !ty.is_method()){
        ty.drop();
        return self.ll.get().loadPtr(val);
      }
      ty.drop();
      return val;
    }
    if let Expr::Lambda(le)=node{
        return val;
    }
    if let Expr::Type(type)=node{
        //ptr to member func
        let rt = self.get_resolver().visit(node);
        if(rt.type.is_fpointer() && rt.method_desc.is_some()){
            return val;
        }
        if(rt.type.is_lambda()){
            return val;
        }
    }
    if let Expr::IfLet(il)=node{
        return val;
    }
    if let Expr::Ques(bx)=node{
      //todo load prim
      return val;
  }
    self.get_resolver().err(node, format("get_obj_ptr {:?}", node));
    std::unreachable!();
  }

  func getTag(self, expr: Expr*): LLVMOpaqueValue*{
    let rt = self.get_resolver().visit(expr);
    let ll = self.ll.get();
    let decl = self.get_resolver().get_decl(&rt).unwrap();
    let tag_idx = get_tag_index(decl);
    let tag = self.get_obj_ptr(expr);
    let mapped = self.mapType(rt.type.deref_ptr());
    rt.drop();
    tag = LLVMBuildStructGEP2(ll.builder, mapped, tag, tag_idx, "".ptr());
    return LLVMBuildLoad2(ll.builder, ll.intTy(ENUM_TAG_BITS()), tag, "".ptr());
  }

  func get_variant_ty(self, decl: Decl*, variant: Variant*): LLVMOpaqueType*{
    let name = format("{:?}::{}", decl.type, variant.name.str());
    let res = *self.protos.get().classMap.get(&name).unwrap();
    name.drop();
    return res;
  }

  func mangle_unit(path: str): String{
    let s1 = path.replace(".", "_");
    let s2 = s1.replace("/", "_");
    let s3 = s2.replace("-", "_");
    s1.drop();
    s2.drop();
    return s3;
  }

  func mangle_static(path: str): String{
    let mangled = mangle_unit(path);
    let res = format("{}_static_init", mangled);
    mangled.drop();
    return res;
  }

  func make_init_proto(self, path: str): Pair<LLVMOpaqueValue*, String>{
    let ll = self.ll.get();
    let ret = LLVMVoidTypeInContext(ll.ctx);
    let args = ptr::null<LLVMOpaqueType*>();
    let ft = LLVMFunctionType(ret, args, 0, LLVMBoolFalse());
    let linkage = LLVMLinkage::LLVMExternalLinkage;
    let mangled = mangle_static(path);
    if(std::getenv("cxx_global").is_some()){
      mangled = "__cxx_global_var_init".owned();
      linkage = LLVMLinkage::LLVMInternalLinkage;
    }
    let mangled_c = mangled.clone().cstr();
    let proto = LLVMAddFunction(ll.module, mangled_c.ptr(), ft);
    LLVMSetLinkage(proto, linkage.int());
    LLVMSetSection(proto, ".text.startup".ptr());
    if(std::getenv("cxx_global").is_some()){
      handle_cxx_global(ll, proto, path);
    }
    return Pair::new(proto, mangled);
  }

  func handle_cxx_global(ll: Emitter*, f: LLVMOpaqueValue*, path: str){
    //_GLOBAL__sub_I_glob.cpp
    let args_ft = ptr::null<LLVMOpaqueType*>();
    let ft = LLVMFunctionType(LLVMVoidTypeInContext(ll.ctx), args_ft, 0, LLVMBoolFalse());
    let linkage = LLVMLinkage::LLVMInternalLinkage;
    let mangled_c = mangle_static(path).cstr();
    let caller_proto = LLVMAddFunction(ll.module, mangled_c.ptr(), ft);
    LLVMSetLinkage(caller_proto, linkage.int());
    LLVMSetSection(caller_proto, ".text.startup".ptr());
    let bb = LLVMAppendBasicBlockInContext(ll.ctx, caller_proto, "".ptr());
    LLVMPositionBuilderAtEnd(ll.builder, bb);
    let args = ptr::null<LLVMOpaqueValue*>();
    //CreateCall(f, args);
    LLVMBuildCall2(ll.builder, ft, f, args, 0, "".ptr());
    LLVMBuildRetVoid(ll.builder);
    mangled_c.drop();
  }

  func do_inline(self, expr: Expr*, ptr_ret: LLVMOpaqueValue*){
    match expr{
      Expr::Call(call) => {
        let rt = self.get_resolver().visit(expr);
        let method = self.get_resolver().get_method(&rt);
        if(method.is_some()){
          self.visit_call2(expr, call, Option::new(ptr_ret), rt);
          return;
        }
        rt.drop();
      },
      Expr::Type(type) => {
        self.simple_enum(type, ptr_ret);
      },
      Expr::Obj(type, args) => {
        self.visit_obj(expr, type, args, ptr_ret);
      },
      Expr::ArrAccess(aa) => {
        self.visit_slice(expr, aa, ptr_ret);
      },
      Expr::Lit(lit) => {
        self.str_lit(lit.val.str(), ptr_ret);
      },
      Expr::Array(list, sz) => {
        self.visit_array(expr, list, sz, ptr_ret);
      },
      _ => {
        panic("inline {:?}", expr);
      }
    }
  }
}

func can_inline(expr: Expr*, r: Resolver*): bool{
  return inline_rvo && doesAlloc(expr, r);
}

func doesAlloc(e: Expr*, r: Resolver*): bool{
  match e{
    Expr::ArrAccess(aa) => return aa.idx2.is_some(),//slice creation
    Expr::Lit(lit) => return lit.kind is LitKind::STR,
    Expr::Type(type) => return true,
    Expr::Array(elems, size) => return true,
    Expr::Obj(type, args) => return true,
    Expr::Call(call) => {
      let rt = r.visit(e);
      if(rt.is_method()){
        let target = r.get_method(&rt).unwrap();
        rt.drop();
        let ret = r.getType(&target.type);
        let res = is_struct(&ret);
        ret.drop();
        return res;
      }
      rt.drop();
      return false;
    },
    _ => return false,
  }
}

func get_tag_index(decl: Decl*): i32{
  assert(decl.is_enum());
  return 0;
}

func get_data_index(decl: Decl*): i32{
  assert(decl.is_enum());
  return 1;
}
