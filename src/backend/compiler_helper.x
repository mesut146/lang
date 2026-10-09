import std/map
import std/libc
import std/stack

import ast/ast
import ast/printer
import ast/utils

import resolver/resolver

import backend/bridge
import backend/emitter
import backend/debug_helper
import backend/expr_emitter
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
       }
       return res;
    }
}


func make_slice_type(ll: LLVMInfo*): llvm_Type*{
  let elems = [ll.intPtr(8), intTy(ll.ctx, SLICE_LEN_BITS())];
  let res = make_struct_ty(ll.ctx, "__slice".ptr(), elems.ptr(), 2);
  return res as llvm_Type*;
}

func make_printf(ll: LLVMInfo*): FunctionInfo{
    let args = [ll.intPtr(8)];
    let ret = intTy(ll.ctx, 32);
    let ft = make_ft(ret, args.ptr(), 1, true);
    let lin = ext();
    let f = make_func(ft, lin, "printf".ptr(), ll.module);
    setCallingConv(f);
    return FunctionInfo{f, ft};
}
func make_sprintf(ll: LLVMInfo*): FunctionInfo{
  let args = [ll.intPtr(8), ll.intPtr(8)];
  let ret = intTy(ll.ctx, 32);
  let ft = make_ft(ret, args.ptr(), 2, true);
  let lin = ext();
  let f = make_func(ft, lin, "sprintf".ptr(), ll.module);
  setCallingConv(f);
  return FunctionInfo{f, ft};
}
func make_fflush(ll: LLVMInfo*): FunctionInfo{
  let args = [ll.intPtr(8)];
  let ret = intTy(ll.ctx, 32);
  let ft = make_ft(ret, args.ptr(), 1, false);
  let lin = ext();
  let f = make_func(ft, lin, "fflush".ptr(), ll.module);
  setCallingConv(f);
  return FunctionInfo{f, ft};
}
func make_malloc(ll: LLVMInfo*): FunctionInfo{
  let args = [intTy(ll.ctx, 64)];
  let ret = ll.intPtr(8);
  let ft = make_ft(ret, args.ptr(), 1, false);
  let lin = ext();
  let f = make_func(ft, lin, "malloc".ptr(), ll.module);
  setCallingConv(f);
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

func all_deps(type: Type*, r: Resolver*, arr: List<String>*){
  if(type.is_any_pointer() || type.is_prim() || type.is_slice()) return;
  if(type.is_array()){
    all_deps(type.elem(), r, arr);
    return;
  }
  let rt = r.visit_type(type);
  let opt = r.get_decl(&rt);
  if(opt.is_none()){
    return;
  }
  arr.add_not_exist(type.print());
  let decl = opt.unwrap();
  all_deps(decl, r, arr);
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

func sort2(list: List<Decl*>*, r: Resolver*){
  //parent -> fields
  let map = Map<String, List<String>>::new();
  //field -> parents
  for (let i = 0; i < list.len(); ++i) {
    let decl = *list.get(i);
    let arr = List<String>::new();
    all_deps(decl, r, &arr);
    map.add(decl.type.print(), arr);
  }
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
        right_all.remove(rpos);
        swap(list, i, j);
        break;
      }
      s2.drop();
    }
  }
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

impl Emitter{
  func get_global_string(self, val: String): Value*{
    let opt = self.string_map.get(&val);
    if(opt.is_some()){
      return *opt.unwrap();
    }
    let val2 = val.clone();
    let val_c = val.cstr();
    let ptr = self.ll.get().glob_str(val2.str());
    self.string_map.add(val2, ptr);
    return ptr;
  }
  func make_proto(self, ft: FunctionType*): llvm_Type*{
    let ret = self.mapType(&ft.return_type);
    let args = List<llvm_Type*>::new();
    for prm in &ft.params{
      args.add(self.mapType(prm));
    }
    let res = make_ft(ret, args.ptr(), ft.params.len() as i32, false);
    return res as llvm_Type*;
  }
  func make_proto(self, ft: LambdaType*): llvm_Type*{
    let ret = self.mapType(ft.return_type.get());
    let args = List<llvm_Type*>::new();
    for prm in &ft.params{
      args.add(self.mapType(prm));
    }
    for prm in &ft.captured{
      args.add(self.mapType(prm));
    }
    let res = make_ft(ret, args.ptr(), args.len() as i32, false);
    return res as llvm_Type*;
  }
  func mapType(self, type: Type*): llvm_Type*{
    let r = self.get_resolver();
    let rt = r.visit_type(type);
    let str = rt.type.print();
    let res = self.mapType2(&rt);
    return res;
  }

  func mapType2(self, rt: RType*): llvm_Type*{
    let ll = self.ll.get();
    let type = &rt.type;
    match type{
      Type::Pointer(elem) =>{
        let elem_ty = self.mapType(elem.get());
        return getPointerTo(elem_ty) as llvm_Type*;
      },
      Type::Array(elem, size) =>{
        let elem_ty = self.mapType(elem.get());
        return ArrayType_get(elem_ty, *size as u32) as llvm_Type*;
      },
      Type::Slice(elem) =>{
        let p = self.protos.get();
        return p.std("slice") as llvm_Type*;
      },
      Type::Function(elem_bx)=>{
        let res = self.make_proto(elem_bx.get());
        return getPointerTo(res as llvm_Type*) as llvm_Type*;
      },
      Type::Lambda(elem_bx)=>{
        let res = self.make_proto(elem_bx.get());
        return getPointerTo(res as llvm_Type*) as llvm_Type*;
      },
      Type::Tuple(tt)=>{
        let name = mangleType(type).cstr();
        let p = self.protos.get();
        let opt = p.classMap.get_str(name.str());
        if(opt.is_some()){
          let res = *opt.unwrap();
          return res as llvm_Type*;
        }
        let elems = List<llvm_Type*>::new(tt.types.len());
        for elem in &tt.types{
          elems.add(self.mapType(elem));
        }
        let res = make_struct_ty(ll.ctx, name.ptr(), elems.ptr(), elems.len() as i32);
        p.classMap.add(name.str().owned(), res as llvm_Type*);
        return res as llvm_Type*;
      },
      Type::Simple(smp) => {
        if(type.is_void()) return getVoidTy(ll.builder);
        if(type.eq("f32")) return getFloatTy(ll.ctx);
        if(type.eq("f64")) return getDoubleTy(ll.ctx);
        let prim_size = prim_size(smp.name.str());
        if(prim_size.is_some()){
          return intTy(ll.ctx, prim_size.unwrap());
        }
        let decl = self.get_resolver().get_decl(rt).unwrap();
        if(decl.is_repr()){
          let at = decl.attr.find("repr").unwrap().args.get(0).print();
          let ty = Type::new(at);
          let res = self.mapType(&ty);
          return res;
        }
        
        let p = self.protos.get();
        let s = type.print();
        if(!p.classMap.contains(&s)){
          //scoped use (M::A) of a decl registered under its own spelling
          //(A): fall back to the decl's canonical name.
          let ds = decl.type.print();
          if(p.classMap.contains(&ds)){
            let res = p.get(&ds);
            return res as llvm_Type*;
          }
          panic("mapType2 {}\n", s);
        }
        let res = p.get(&s);
        return res as llvm_Type*;
      }
    }
  }

  //normal decl protos and di protos
  func make_decl_protos(self){
    let p = self.protos.get();
    let resolver = self.get_resolver();
    let list = List<Decl*>::new();
    getTypes(&self.unit().items, &list);
    for rt in &resolver.used_types{
      let decl = resolver.get_decl(rt).unwrap();
      if (decl.is_generic) continue;
      list.add(decl);
    }
    sort2(&list, resolver);
    //first create just protos to fill later
    for(let i = 0;i < list.len();++i){
      let decl = *list.get(i);
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
        let var_ty = make_struct_ty2(ll.ctx, name_c.ptr());
        name_c.drop();
        p.classMap.add(name, var_ty as llvm_Type*);
      }
    }
    let type_c = decl.type.print().cstr();
    let st = make_struct_ty2(ll.ctx, type_c.ptr());
    p.classMap.add(decl.type.print(), st as llvm_Type*);
  }

  func fill_decl(self, decl: Decl*, st: llvm_Type*){
    let p = self.protos.get();
    let ll = self.ll.get();
    let elems = List<llvm_Type*>::new();
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
        elems.add(intTy(ll.ctx, ENUM_TAG_BITS()));
        elems.add(ArrayType_get(intTy(ll.ctx, 8), max / 8) as llvm_Type*);
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
    StructType_setBody(st as StructType*, elems.ptr(), elems.len() as i32);
  }
  func make_variant_type(self, ev: Variant*, decl: Decl*, name: String*, ty: llvm_Type*){
    let elems = List<llvm_Type*>::new();
    if(decl.base.is_some()){
      elems.add(self.mapType(decl.base.get()));
    }
    for(let j = 0;j < ev.fields.len();++j){
      let fd = ev.fields.get(j);
      let ft = self.mapType(&fd.type);
      elems.add(ft);
    }
    StructType_setBody(ty as StructType*, elems.ptr(), elems.len() as i32);
  }

  func make_proto(self, m: Method*): Option<FunctionInfo>{
    let ll = self.ll.get();
    if(m.is_generic) return Option<FunctionInfo>::new();
    let mangled = mangle(m);
    if(self.protos.get().funcMap.contains(&mangled)){
      panic("already proto {}\n", mangled);
    }
    let sig = MethodSig::new(m, self.get_resolver());
    let rvo = is_struct(&sig.ret);
    let ret_real = self.mapType(&sig.ret);
    let ret = getVoidTy(ll.builder);
    if(is_main(m)){
      ret = intTy(ll.ctx, 32);
    }else if(!rvo){
      ret = ret_real;
    }
    let args = List<llvm_Type*>::new();
    if(rvo){
      let rvo_ty = getPointerTo(self.mapType(&sig.ret));
      args.add(rvo_ty as llvm_Type*);
    }
    for prm_type in &sig.params{
      let pt = self.mapType(prm_type);
      if(is_struct(prm_type)){
        args.add(getPointerTo(pt) as llvm_Type*);
      }else{
        args.add(pt);
      }
    }
    let ft = make_ft(ret, args.ptr(), args.len() as i32, m.is_vararg);
    let linkage = ext();
    if(!m.type_params.empty()){
      linkage = odr();
    }else if let Parent::Impl(info)=&m.parent{
      if(info.type.is_simple() && !info.type.get_args().empty()){
        linkage = odr();
      }
    }
    let mangled_c = mangled.clone().cstr();
    let f = make_func(ft, linkage, mangled_c.ptr(), ll.module);
    if(rvo){
      let arg = Function_getArg(f, 0);
      Argument_setname(arg, "_ret".ptr());
      Argument_setsret(ll.ctx, arg, ret_real);
    }
    self.protos.get().funcMap.add(mangled, FunctionInfo{f, ft});
    return Option::new(FunctionInfo{f, ft});
  }

  func getSize(self, type: Type*): i64{
    let ll = self.ll.get();
    match type{
      Type::Pointer(bx) => return POINTER_SIZE,
      Type::Function(bx) => return POINTER_SIZE,
      Type::Lambda(bx) => return POINTER_SIZE,
      Type::Slice(bx) => {
        let st = self.protos.get().std("slice");
        return ll.sizeOf(st);
        //return self.ll.get().sizeOf(st as llvm_Type*);
      },
      Type::Array(elem, size) => {
        return self.getSize(elem.get()) * (*size);
      },
      Type::Tuple(tt) => {
        let rt = self.get_resolver().visit_type(type);
        let mapped = self.mapType(&rt.type);
        return ll.sizeOf(mapped);
      },
      Type::Simple(smp) => {
        if(type.is_prim()){
          return prim_size(type.name().str()).unwrap();
        }
        let rt = self.get_resolver().visit_type(type);
        if(rt.is_decl()){
          let decl = self.get_resolver().get_decl(&rt).unwrap();
          return self.getSize(decl);
        }
        panic("no decl");
      }
    }
  }

  func getSize(self, decl: Decl*): i64{
    let mapped = self.mapType(&decl.type);
    return self.ll.get().sizeOf(mapped);
  }

  func cast_expr(self, expr: Expr*, target_type: Type*): Value*{
    let ll = self.ll.get();
    let src_type = self.get_resolver().getType(expr);
    let val = self.load_expr(expr);
    let is_unsigned = isUnsigned(&src_type);
    let target_ty = self.mapType(target_type);

    if(target_type.is_float()){
      if(src_type.is_float()){
        if(src_type.eq("f32")){
          //f32 -> f64
          return CreateFPExt(ll.builder, val, target_ty);
        }else{
          //f64 -> f32
          return CreateFPTrunc(ll.builder, val, target_ty);
        }
      }else{
        if(is_unsigned){
          return CreateUIToFP(ll.builder, val, target_ty);
        }else{
          return CreateSIToFP(ll.builder, val, target_ty);
        }
      }
    }
    if(src_type.is_float()){
      if(is_unsigned){
        return CreateFPToUI(ll.builder, val, target_ty);
      }else{
        return CreateFPToSI(ll.builder, val, target_ty);
      }
    }
    let val_ty = Value_getType(val);
    let src_size = ll.sizeOf(val_ty);
    let trg_size = self.getSize(target_type);
    let trg_ty = intTy(ll.ctx, trg_size as i32);
    if(src_size < trg_size){
      if(is_unsigned){
        return CreateZExt(ll.builder, val, trg_ty);
      }else{
        return CreateSExt(ll.builder, val, trg_ty);
      }
    }else if(src_size > trg_size){
      return CreateTrunc(ll.builder, val, trg_ty);
    }
    return val;
  }
  
  func cast_value(self, val: Value*, src_type: Type*, target_type: Type*): Value*{
    let is_unsigned = isUnsigned(src_type);
    let ll = self.ll.get();
    let val_ty = Value_getType(val);
    let src_size = ll.sizeOf(val_ty);
    let trg_size = self.getSize(target_type);
    let trg_ty = intTy(ll.ctx, trg_size as i32);
    if(src_size < trg_size){
      if(is_unsigned){
        return CreateZExt(ll.builder, val, trg_ty);
      }else{
        return CreateSExt(ll.builder, val, trg_ty);
      }
    }else if(src_size > trg_size){
      return CreateTrunc(ll.builder, val, trg_ty);
    }
    return val;
  }

  func load_expr(self, expr: Expr*): Value*{
    let val = self.visit(expr);
    let ll = self.ll.get();
    let ty = Value_getType(val);
    if(!isPointerTy(ty)) return val;
    let type = self.getType(expr);
    assert(is_loadable(&type));
    let res = CreateLoad(ll.builder, self.mapType(&type), val);//local var
    return res;
  }

  func load_if_ptr(self, val: Value*, type: Type*): Value*{
    assert(is_loadable(type));
    let ll = self.ll.get();
    let ty = Value_getType(val);
    if(!isPointerTy(ty)) return val;
    let res = CreateLoad(ll.builder, self.mapType(type), val);//local var
    return res;
  }

  func store(self, expr: Expr*, type: Type*, trg: Value*){
    self.store(expr, type, trg, Option<Expr*>::new());
  }
  func store(self, expr: Expr*, type: Type*, trg: Value*, lhs: Option<Expr*>){
      let rt = self.get_resolver().visit_type(type);
      self.store(expr, &rt, trg, lhs);
  }
  func store(self, expr: Expr*, rt: RType*, trg: Value*, lhs: Option<Expr*>){
      let type = &rt.type;
      let ll = self.ll.get();
      if(is_struct(type)){
        if(self.can_inline(expr)){
          //todo own drop_lhs
          self.do_inline(expr, trg);
          return;
        }
        let val = self.visit(expr);
        if(lhs.is_some()){
          self.own.get().drop_lhs(lhs.unwrap(), LLVMPtr::new(trg));
        }
        self.copy(trg, val, type);
      }else if(type.is_any_pointer()){
        let val = self.eval_operand(expr);
        CreateStore(ll.builder, val, trg);
      }else{
        let val = self.cast_expr(expr, type);
        CreateStore(ll.builder, val, trg); 
      }
  }

  //returns 1 bit for br
  func branch(self, expr: Expr*): Value*{
    let val = self.load_expr(expr);
    let ll = self.ll.get();
    return CreateTrunc(ll.builder, val, intTy(ll.ctx, 1));
  }
  //returns 1 bit for br
  func branch(self, val: Value*): Value*{
    let ll = self.ll.get();
    return CreateTrunc(ll.builder, val, intTy(ll.ctx, 1));
  }

  func load(self, val: Value*, ty: Type*): Value*{
    let mapped = self.mapType(ty);
    let ll = self.ll.get();
    return CreateLoad(ll.builder, mapped, val);
  }


  //Normalize any expression to the pointer-or-value its emitter needs:
  //value-producing forms evaluate to a ready value, place forms evaluate
  //to an address (loaded through only when the place itself is pointer
  //typed). Every Expr variant is accounted for below; the ones that can
  //never be an operand address fail loudly instead of miscompiling.
  func eval_operand(self, node: Expr*): Value*{
    //Parens unwrap before evaluation: visiting the paren would emit the
    //inner expression, and the recursion below would emit it again.
    if let Expr::Par(e)=node{
      return self.eval_operand(e.get());
    }
    //single evaluation: every arm below returns either this value or a
    //load through it, never re-visits (re-visiting would emit twice).
    let val = self.visit(node);
    match node{
      Expr::Par(e) => {
        //dead: caught above, but the exhaustiveness checker requires
        //every variant to appear in the match.
        std::unreachable!();
      },
      Expr::Unary(op, e) => {
        return val;
      },
      Expr::Obj(type, args) => {
        return val;
      },
      Expr::Call(mc) => {
        return val;
      },
      Expr::MacroCall(mc) => {
        return val;
      },
      Expr::Lit(lit) => {
        return val;
      },
      Expr::As(e, type) => {
        return val;
      },
      Expr::Infix(op, l, r) => {
        return val;
      },
      Expr::Name(nm) => {
        return self.eval_place(node, val);
      },
      Expr::ArrAccess(aa) => {
        return self.eval_place(node, val);
      },
      Expr::Access(scope, name) => {
        return self.eval_place(node, val);
      },
      Expr::Lambda(le) => {
        return val;
      },
      Expr::Type(type) => {
        //ptr to member func
        let rt = self.get_resolver().visit(node);
        if(rt.type.is_fpointer() && rt.method_desc.is_some()){
            return val;
        }
        if(rt.type.is_lambda()){
            return val;
        }
      },
      Expr::IfLet(il) => {
        return val;
      },
      Expr::Ques(bx) => {
        //todo load prim
        return val;
      },
      Expr::Is(e, rhs) => {
      },
      Expr::Array(list, size) => {
        //visit above already emitted the storage and returns its pointer,
        //which is exactly what operand users (GEP) need: a value, not a
        //place to load through.
        return val;
      },
      Expr::Tuple(elems) => {
        //same as Array: visit returns the tuple storage pointer.
        return val;
      },
      Expr::Block(x) => {
      },
      Expr::If(e) => {
      },
      Expr::Match(m) => {
      },
    }
    self.get_resolver().err(node, format("eval_operand {:?}", node));
    std::unreachable!();
  }

  //Place forms (Name, ArrAccess, Access) given their already-visited
  //value: the address itself, loaded through one level when the place
  //is pointer-typed (and not a method value).
  func eval_place(self, node: Expr*, val: Value*): Value*{
    let ty = self.get_resolver().visit(node);
    if(ty.type.is_any_pointer() && !ty.is_method()){
      return self.ll.get().loadPtr(val);
    }
    return val;
  }

  func getTag(self, expr: Expr*): Value*{
    let rt = self.get_resolver().visit(expr);
    let ll = self.ll.get();
    let decl = self.get_resolver().get_decl(&rt).unwrap();
    let tag_idx = get_tag_index(decl);
    let tag = self.eval_operand(expr);
    let mapped = self.mapType(rt.type.deref_ptr());
    tag = CreateStructGEP(ll.builder, mapped, tag, tag_idx);
    return CreateLoad(ll.builder, intTy(ll.ctx, ENUM_TAG_BITS()), tag);
  }

  func get_variant_ty(self, decl: Decl*, variant: Variant*): llvm_Type*{
    let name = format("{:?}::{}", decl.type, variant.name.str());
    let res = *self.protos.get().classMap.get(&name).unwrap();
    return res;
  }

  func mangle_unit(path: str): String{
    let s1 = path.replace(".", "_");
    let s2 = s1.replace("/", "_");
    let s3 = s2.replace("-", "_");
    return s3;
  }

  func mangle_static(path: str): String{
    let mangled = mangle_unit(path);
    let res = format("{}_static_init", mangled);
    return res;
  }

  func make_init_proto(self, path: str): Pair<Function*, String>{
    let ll = self.ll.get();
    let ret = getVoidTy(ll.builder);
    let args = ptr::null<llvm_Type*>();
    let ft = make_ft(ret, args, 0, false);
    let linkage = ext();
    let mangled = mangle_static(path);
    if(std::getenv("cxx_global").is_some()){
      mangled = "__cxx_global_var_init".owned();
      linkage = internal();
    }
    let mangled_c = mangled.clone().cstr();
    let proto = make_func(ft, linkage, mangled_c.ptr(), ll.module);
    setSection(proto, ".text.startup".ptr());
    if(std::getenv("cxx_global").is_some()){
      handle_cxx_global(ll, proto, path);
    }
    return Pair::new(proto, mangled);
  }

  func handle_cxx_global(ll: LLVMInfo*, f: Function*, path: str){
    //_GLOBAL__sub_I_glob.cpp
    let args_ft = ptr::null<llvm_Type*>();
    let ft = make_ft(getVoidTy(ll.builder), args_ft, 0, false);
    let linkage = internal();
    let mangled_c = mangle_static(path).cstr();
    let caller_proto = make_func(ft, linkage, mangled_c.ptr(), ll.module);
    
    setSection(caller_proto, ".text.startup".ptr());
    let bb = create_bb(ll.ctx, "".ptr(), caller_proto);
    SetInsertPoint(ll.builder, bb);
    let args = ptr::null<Value*>();
    CreateCall(ll.builder, f, args, 0);
    CreateRetVoid(ll.builder);
  }

  func do_inline(self, expr: Expr*, ptr_ret: Value*){
    match expr{
      Expr::Call(call) => {
        let rt = self.get_resolver().visit(expr);
        let method = self.get_resolver().get_method(&rt);
        if(method.is_some()){
          self.visit_call2(expr, call, Option::new(ptr_ret), rt);
          return;
        }
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

  func can_inline(self, expr: Expr*): bool{
    return self.config.inline_rvo && doesAlloc(expr, self.get_resolver());
  }
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
        let ret = r.getType(&target.type);
        let res = is_struct(&ret);
        return res;
      }
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
