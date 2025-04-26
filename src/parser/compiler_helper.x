import parser/bridge
import parser/ast
import parser/resolver
import parser/compiler
import parser/debug_helper
import parser/utils
import parser/printer
import parser/expr_emitter
import parser/ownership
import parser/own_model
import std/map
import std/libc
import std/stack

struct RvalueHelper {
  rvalue: bool;
  scope: Option<Expr*>;
  scope_type: Option<Type>;
}

impl RvalueHelper{
    func is_rvalue(e: Expr*): bool{
      if let Expr::Par(inner*) = (e){
        return is_rvalue(inner.get());
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


func make_slice_type(): StructType*{
    let elems = vector_Type_new();
    vector_Type_push(elems, getPointerTo(getInt(8)) as llvm_Type*);
    vector_Type_push(elems, getInt(SLICE_LEN_BITS()));
    let res = make_struct_ty2("__slice".ptr(), elems);
    vector_Type_delete(elems);
    return res;
}

func make_printf(): Function*{
    let args = vector_Type_new();
    vector_Type_push(args, getPointerTo(getInt(8)) as llvm_Type*);
    let ft = make_ft(getInt(32), args, true);
    let f = make_func(ft, ext(), "printf".ptr());
    setCallingConv(f);
    vector_Type_delete(args);
    return f;
}
func make_sprintf(): Function*{
  let args = vector_Type_new();
  vector_Type_push(args, getPointerTo(getInt(8)) as llvm_Type*);
  vector_Type_push(args, getPointerTo(getInt(8)) as llvm_Type*);
  let ft = make_ft(getInt(32), args, true);
  let f = make_func(ft, ext(), "sprintf".ptr());
  setCallingConv(f);
  vector_Type_delete(args);
  return f;
}
func make_fflush(): Function*{
    let args = vector_Type_new();
    vector_Type_push(args, getPointerTo(getInt(8)) as llvm_Type*);
    let ft = make_ft(getInt(32), args, false);
    let f = make_func(ft, ext(), "fflush".ptr());
    setCallingConv(f);
    vector_Type_delete(args);
    return f;
}
func make_malloc(): Function*{
    let args = vector_Type_new();
    vector_Type_push(args, getInt(64));
    let ft = make_ft(getPointerTo(getInt(8)) as llvm_Type*, args, false);
    let f = make_func(ft, ext(), "malloc".ptr());
    setCallingConv(f);
    vector_Type_delete(args);
    return f;
}

func getTypes(unit: Unit*, list: List<Decl*>*){
    for (let i = 0;i < unit.items.len();++i) {
        let item = unit.items.get(i);
        if let Item::Decl(d*)=(item){
            if(d.is_generic) continue;
            list.add(d);
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
    Decl::Struct(fields*)=>{
      for (let j = 0; j < fields.len(); ++j) {
        let fd = fields.get(j);
        //add_type(res, &fd.type);
        all_deps(&fd.type, r, res);
      }
    },
    Decl::Enum(variants*)=>{
      for (let j = 0; j < variants.len(); ++j) {
        let ev = variants.get(j);
        for (let k = 0; k < ev.fields.len(); ++k) {
          let fd = ev.fields.get(k);
          //add_type(res, &fd.type);
          all_deps(&fd.type, r, res);
        }
      }
    },
    Decl::TupleStruct(fields*)=>{
      for ft in fields{
        //add_type(res, &ft);
        all_deps(ft, r, res);
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

/*func sort3(list: List<Decl*>*, r: Resolver*){
  //parent -> fields
  let map = Map<String, List<String>>::new();
  //ch -> parents
  let map2 = Map<String, List<String>>::new();
  for (let i = 0; i < list.len(); ++i) {
    let decl = *list.get(i);
    let tstr = decl.type.print();
    if(!map.contains(&tstr)){
      map.add(tstr.clone(), List<String>::new());
    }
    let deps_arr = map.get(&tstr).unwrap();
    if(decl.is_struct()){
      let fields = decl.get_fields();
      for (let j = 0; j < fields.len(); ++j) {
        let fd = fields.get(j);
        let field_str = fd.type.print();
        deps_arr.add(field_str.clone());
        let parents = &map2.get_pair_or(field_str.clone(), List<String>::new()).b;
        parents.add(tstr.clone());
        //find parent of decl & merge children
        let p_arr = map2.get(&tstr).unwrap();
        for parent in p_arr{
          //let other_ch_arr = map.get_pair_or(parent);
        }
        field_str.drop();
      }
    }else{
      let variants = decl.get_variants();
      for (let j = 0; j < variants.len(); ++j) {
        let ev = variants.get(j);
        for (let k = 0; k < ev.fields.len(); ++k) {
          let fd = ev.fields.get(k);
          deps_arr.add(fd.type.print());
          
        }
      }
    }
    tstr.drop();
  }
  for (let i = 0; i < list.len(); ++i) {
    //find decl belongs to i'th index
    for (let j = 0; j < list.len() - 1; ++j) {
      let d1: Decl* = *list.get(j);
      let d2: Decl* = *list.get(j + 1);
      //is d1 is parent of d2, swap
      let s1 = d1.type.print();
      let s2 = d2.type.print();
      let chs = map.get(&s2).unwrap();
      if(chs.contains(&s1)){
        swap(list, j, j + 1);
      }
      s2.drop();
    }
  }
  map.drop();
}*/

func swap(list: List<Decl*>*, i: i32, j: i32){
  let a = *list.get(i);
  let b = *list.get(j);
  list.set(j, a);
  list.set(i, b);
}

func getMethods(unit: Unit*): List<Method*>{
  let list = List<Method*>::new(100);
  for (let i = 0;i < unit.items.len();++i) {
    let item = unit.items.get(i);
    if let Item::Method(m*)=(item){
        if(m.is_generic) continue;
        list.add(m);
    }else if let Item::Impl(imp*)=(item){
      if(!imp.info.type_params.empty()) continue;
      for(let j = 0;j < imp.methods.len();++j){
        list.add(imp.methods.get(j));
      }
    }else if let Item::Extern(methods*)=(item){
      for(let j = 0;j < methods.len();++j){
        list.add(methods.get(j));
      }
    }
  }
  //broken after expand, ptr
  return list;
}

impl Compiler{
  func get_global_string(self, val: String): Value*{
    let opt = self.string_map.get(&val);
    if(opt.is_some()){
      val.drop();
      return *opt.unwrap();
    }
    let val2 = val.clone();
    let val_c = val.cstr();
    let ptr = CreateGlobalStringPtr(val_c.ptr());
    self.string_map.add(val2, ptr);
    val_c.drop();
    return ptr;
  }
  func make_proto(self, ft: FunctionType*): llvm_FunctionType*{
    let ret = self.mapType(&ft.return_type);
    let args = vector_Type_new();
    for prm in &ft.params{
      vector_Type_push(args, self.mapType(prm));
    }
    let res = make_ft(ret, args, false);
    vector_Type_delete(args);
    return res;
  }
  func make_proto(self, ft: LambdaType*): llvm_FunctionType*{
    let ret = self.mapType(ft.return_type.get());
    let args = vector_Type_new();
    for prm in &ft.params{
      vector_Type_push(args, self.mapType(prm));
    }
    for prm in &ft.captured{
      vector_Type_push(args, self.mapType(prm));
    }
    let res = make_ft(ret, args, false);
    vector_Type_delete(args);
    return res;
  }
  func mapType(self, type: Type*): llvm_Type*{
    let r = self.get_resolver();
    let rt = r.visit_type(type);
    let str = rt.type.print();
    let res = self.mapType(&rt.type, &str);
    rt.drop();
    str.drop();
    return res;
  }
  func mapType(self, type: Type*, s: String*): llvm_Type*{
    if(type.is_void()) return getVoidTy();
    if(type.eq("f32")){
      return getFloatTy();
    }
    if(type.eq("f64")){
      return getDoubleTy();
    }
    let prim_size = prim_size(s.str());
    if(prim_size.is_some()){
      return getInt(prim_size.unwrap());
    }
    if let Type::Array(elem*,size)=(type){
      let elem_ty = self.mapType(elem.get());
      return getArrTy(elem_ty, size) as llvm_Type*;
    }
    if let Type::Pointer(elem*)=(type){
      let elem_ty = self.mapType(elem.get());
      return getPointerTo(elem_ty) as llvm_Type*;
    }
    if let Type::Function(elem_bx*)=(type){
      let res = self.make_proto(elem_bx.get());
      //return res as llvm_Type*;
      return getPointerTo(res as llvm_Type*) as llvm_Type*;
    }
    if let Type::Lambda(elem_bx*)=(type){
      let res = self.make_proto(elem_bx.get());
      //return res as llvm_Type*;
      return getPointerTo(res as llvm_Type*) as llvm_Type*;
    }
    let p = self.protos.get();
    if let Type::Slice(elem*)=(type){
      return p.std("slice") as llvm_Type*;
    }
    if(!p.classMap.contains(s)){
      panic("mapType {}\n", s);
    }
    return p.get(s);
  }

  //normal decl protos and di protos
  func make_decl_protos(self){
    let p = self.protos.get();
    let resolver = self.get_resolver();
    let list = List<Decl*>::new();
    getTypes(self.unit(), &list);
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
      self.fill_decl(decl, p.get(decl) as StructType*);
    }
    if(self.llvm.di.get().debug){
      //di proto
      for(let i = 0;i < list.len();++i){
        let decl = *list.get(i);
        self.llvm.di.get().map_di_proto(decl, self);
      }
      //di fill
      for(let i = 0;i < list.len();++i){
        let decl = *list.get(i);
        self.llvm.di.get().map_di_fill(decl, self);
      }
    }
    list.drop();
  }

  func make_decl_proto(self, decl: Decl*){
    let p = self.protos.get();
    if(decl.is_enum()){
      let vars = decl.get_variants();
      for(let i = 0;i < vars.len();++i){
        let ev = vars.get(i);
        let name = format("{:?}::{}", decl.type, ev.name);
        let name_c = name.clone().cstr();
        let var_ty = make_struct_ty(name_c.ptr());
        name_c.drop();
        p.classMap.add(name, var_ty as llvm_Type*);
      }
    }
    let type_c = decl.type.print().cstr();
    let st = make_struct_ty(type_c.ptr());
    type_c.drop();
    p.classMap.add(decl.type.print(), st as llvm_Type*);
  }

  func fill_decl(self, decl: Decl*, st: StructType*){
    let p = self.protos.get();
    let elems = vector_Type_new();
    match decl{
      Decl::Enum(variants*)=>{
        //calc enum size
        let max = 0;
        for(let i = 0;i < variants.len();++i){
          let ev = variants.get(i);
          let name = format("{:?}::{}", decl.type, ev.name.str());
          let var_ty = p.get(&name) as StructType*;
          self.make_variant_type(ev, decl, &name, var_ty);
          let variant_size = getSizeInBits(var_ty);
          if(variant_size > max){
            max = variant_size;
          }
          name.drop();
        }
        vector_Type_push(elems, getInt(ENUM_TAG_BITS()));
        vector_Type_push(elems, getArrTy(getInt(8), max / 8) as llvm_Type*);
      },
      Decl::Struct(fields*)=>{
        if(decl.base.is_some()){
          vector_Type_push(elems, self.mapType(decl.base.get()));
        }
        for(let i = 0;i < fields.len();++i){
          let fd = fields.get(i);
          let ft = self.mapType(&fd.type);
          vector_Type_push(elems, ft);
        }
      },
      Decl::TupleStruct(fields*)=>{
        for ft in fields{
          let ft2 = self.mapType(ft);
          vector_Type_push(elems, ft2);
        }
      }
    }
    setBody(st, elems);
    vector_Type_delete(elems);
    //print("fill_decl {}\n", &decl.type);
    //Type_dump(st as llvm_Type*);
    //let size = getSizeInBits(st);
    /*if(size == 0){
      print("fill_decl sizeof {}={}\n", &decl.type, size);
    }*/
  }
  func make_variant_type(self, ev: Variant*, decl: Decl*, name: String*, ty: StructType*){
    let elems = vector_Type_new();
    if(decl.base.is_some()){
      vector_Type_push(elems, self.mapType(decl.base.get()));
    }
    for(let j = 0;j < ev.fields.len();++j){
      let fd = ev.fields.get(j);
      let ft = self.mapType(&fd.type);
      vector_Type_push(elems, ft);
    }
    setBody(ty, elems);
    vector_Type_delete(elems);
  }

  func make_proto(self, m: Method*): Option<Function*>{
    if(m.is_generic) return Option<Function*>::new();
    let mangled = mangle(m);
    //print("proto {}\n", mangled);
    if(self.protos.get().funcMap.contains(&mangled)){
      panic("already proto {}\n", mangled);
    }
    let sig = MethodSig::new(m, self.get_resolver());
    let rvo = is_struct(&m.type);
    let ret = getVoidTy();
    if(is_main(m)){
      ret = getInt(32);
    }else if(!rvo){
      ret = self.mapType(&sig.ret);
    }
    let args = vector_Type_new();
    if(rvo){
      let rvo_ty = getPointerTo(self.mapType(&sig.ret)) as llvm_Type*;
      vector_Type_push(args, rvo_ty);
    }
    for prm_type in &sig.params{
      let pt = self.mapType(prm_type);
      if(is_struct(prm_type)){
        vector_Type_push(args, getPointerTo(pt) as llvm_Type*);
      }else{
        vector_Type_push(args, pt);
      }
    }
    let ft = make_ft(ret, args, m.is_vararg);
    let linkage = ext();
    if(!m.type_params.empty()){
      linkage = odr();
    }else if let Parent::Impl(info*)=(&m.parent){
      if(info.type.is_simple() && !info.type.get_args().empty()){
        linkage = odr();
      }
    }
    let mangled_c = mangled.clone().cstr();
    let f = make_func(ft, linkage, mangled_c.ptr());
    if(rvo){
      let arg = get_arg(f, 0);
      Argument_setname(arg, "ret".ptr());
      Argument_setsret(arg, self.mapType(&sig.ret));
    }
    self.protos.get().funcMap.add(mangled, f);
    vector_Type_delete(args);
    mangled_c.drop();
    sig.drop();
    return Option::new(f);
  }

  func getSize(self, type: Type*): i64{
    if(type.is_prim()){
      return prim_size(type.name().str()).unwrap();
    }
    if(type.is_any_pointer()) return 64;
    if(type is Type::Lambda) return 64;
    if let Type::Array(elem*, sz)=(type){
      return self.getSize(elem.get()) * sz;
    }
    if let Type::Slice(elem*)=(type){
      let st = self.protos.get().std("slice");
      return getSizeInBits(st);
    }
    let rt = self.get_resolver().visit_type(type);
    if(rt.is_decl()){
      let decl = self.get_resolver().get_decl(&rt).unwrap();
      rt.drop();
      return self.getSize(decl);
    }
    rt.drop();
    panic("getSize {:?}", type);
  }

  func getSize(self, decl: Decl*): i64{
    let mapped = self.mapType(&decl.type);
    return getSizeInBits(mapped as StructType*);
  }

  func cast(self, expr: Expr*, target_type: Type*): Value*{
    let src_type = self.get_resolver().getType(expr);
    let val = self.loadPrim(expr);
    /*if(src_type.eq(target_type)){
      if(src_type.eq("bool")){

      }
      src_type.drop();
      return val;
    }*/
    let is_unsigned = isUnsigned(&src_type);
    let target_ty = self.mapType(target_type);

    if(target_type.is_float()){
      if(src_type.is_float()){
        if(src_type.eq("f32")){
          //f32 -> f64
          src_type.drop();
          return CreateFPExt(val, target_ty);
        }else{
          //f64 -> f32
          src_type.drop();
          return CreateFPTrunc(val, target_ty);
        }
      }else{
        if(is_unsigned){
          src_type.drop();
          return CreateUIToFP(val, target_ty);
        }else{
          src_type.drop();
          return CreateSIToFP(val, target_ty);
        }
      }
    }
    if(src_type.is_float()){
      if(is_unsigned){
        src_type.drop();
        return CreateFPToUI(val, target_ty);
      }else{
        src_type.drop();
        return CreateFPToSI(val, target_ty);
      }
    }
    let val_ty = Value_getType(val);
    let src_size = getPrimitiveSizeInBits(val_ty);
    let trg_size = self.getSize(target_type);
    let trg_ty = getInt(trg_size as i32);
    if(src_size < trg_size){
      if(is_unsigned){
        src_type.drop();
        return CreateZExt(val, trg_ty);
      }else{
        src_type.drop();
        return CreateSExt(val, trg_ty);
      }
    }else if(src_size > trg_size){
      src_type.drop();
      return CreateTrunc(val, trg_ty);
    }
    src_type.drop();
    return val;
  }
  
  func cast2(self, val: Value*, src_type: Type*, target_type: Type*): Value*{
    let is_unsigned = isUnsigned(src_type);
    let val_ty = Value_getType(val);
    let src_size = getPrimitiveSizeInBits(val_ty);
    let trg_size = self.getSize(target_type);
    let trg_ty = getInt(trg_size as i32);
    if(src_size < trg_size){
      if(is_unsigned){
        return CreateZExt(val, trg_ty);
      }else{
        return CreateSExt(val, trg_ty);
      }
    }else if(src_size > trg_size){
      return CreateTrunc(val, trg_ty);
    }
    return val;
  }

  func loadPrim(self, expr: Expr*): Value*{
    let val = self.visit(expr);
    let ty = Value_getType(val);
    if(!isPointerTy(ty)) return val;
    let type = self.getType(expr);
    assert(is_loadable(&type));
    let res = CreateLoad(self.mapType(&type), val);//local var
    type.drop();
    return res;
  }

  func loadPrim(self, val: Value*, type: Type*): Value*{
    assert(is_loadable(type));
    let ty = Value_getType(val);
    if(!isPointerTy(ty)) return val;
    let res = CreateLoad(self.mapType(type), val);//local var
    return res;
  }

  func setField(self, expr: Expr*, type: Type*, trg: Value*){
    self.setField(expr, type, trg, Option<Expr*>::new());
  }
  func setField(self, expr: Expr*, type: Type*, trg: Value*, lhs: Option<Expr*>){
      let rt = self.get_resolver().visit_type(type);
      self.setField(expr, &rt, trg, lhs);
      rt.drop();
  }
  func setField(self, expr: Expr*, rt: RType*, trg: Value*, lhs: Option<Expr*>){
      let type = &rt.type;
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
        CreateStore(val, trg);
      }else{
        let val = self.cast(expr, type);
        CreateStore(val, trg); 
      }
  }

  //returns 1 bit for br
  func branch(self, expr: Expr*): Value*{
    let val = self.loadPrim(expr);
    return CreateTrunc(val, getInt(1));
  }
  //returns 1 bit for br
  func branch(self, val: Value*): Value*{
    return CreateTrunc(val, getInt(1));
  }

  func load(self, val: Value*, ty: Type*): Value*{
    let mapped = self.mapType(ty);
    return CreateLoad(mapped, val);
  }

  func emit_as_arg(self, node: Expr*): Value*{
    match node{
      Lit(val*)=>{
        return self.visit(node);
      },
      Name(val*)=>{
        //todo
      },
      Call(mc*) => {
        return self.visit(node);
      },
      MacroCall(mc*) => {
        return self.visit(node);
      },
      Par(e*) => {
        return self.visit(node);
      },
      Type(val*) => {
        return self.visit(node);
      },
      Unary(op*, e*) => {
        return self.visit(node);
      },
      Infix(op*, l*, r*) => {
        return self.visit(node);
      },
      Access(scope*, name*) => {
        //todo
      },
      Obj(type*, args*) => {
        return self.visit(node);
      },
      As(e*, type*) => {

      },
      Is(e*, rhs*) => {
        return self.visit(node);
      },
      Array(list*, size) => {
        return self.visit(node);
      },
      ArrAccess(val*) => {

      },
      Match(val*) => {
        //todo
      },
      Block(x*) => {

      },
      If(is*) => {

      },
      IfLet(il*) => {

      },
      Lambda(val*) => {
        return self.visit(node);
      },
      Ques(e*) => {
        return self.visit(node);
      },
    }
    panic("todo");
  }

  func get_obj_ptr(self, node: Expr*): Value*{
    if let Expr::Par(e*)=(node){
      return self.get_obj_ptr(e.get());
    }
    if let Expr::Unary(op*,e*)=(node){
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
        return CreateLoad(getPtr(), val);
      }
      ty.drop();
      return val;
    }
    if let Expr::Lambda(le*)=(node){
        return val;
    }
    if let Expr::Type(type*)=(node){
        //ptr to member func
        let rt = self.get_resolver().visit(node);
        if(rt.type.is_fpointer() && rt.method_desc.is_some()){
            return val;
        }
        if(rt.type.is_lambda()){
            return val;
        }
    }
    if let Expr::IfLet(il*)=(node){
        return val;
    }
    if let Expr::Ques(bx*)=(node){
      //todo load prim
      return val;
  }
    self.get_resolver().err(node, format("get_obj_ptr {:?}", node));
    std::unreachable();
  }

  func getTag(self, expr: Expr*): Value*{
    let rt = self.get_resolver().visit(expr);
    let decl = self.get_resolver().get_decl(&rt).unwrap();
    let tag_idx = get_tag_index(decl);
    let tag = self.get_obj_ptr(expr);
    let mapped = self.mapType(rt.type.deref_ptr());
    rt.drop();
    tag = CreateStructGEP(tag, tag_idx, mapped);
    return CreateLoad(getInt(ENUM_TAG_BITS()), tag);
  }

  func get_variant_ty(self, decl: Decl*, variant: Variant*): llvm_Type*{
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

  func make_init_proto(self, path: str): Pair<Function*, String>{
    let ret = getVoidTy();
    let args = vector_Type_new();
    let ft = make_ft(ret, args, false);
    let linkage = ext();
    let mangled = mangle_static(path);
    if(std::getenv("cxx_global").is_some()){
      mangled = "__cxx_global_var_init".owned();
      linkage = internal();
    }
    let mangled_c = mangled.clone().cstr();
    let proto = make_func(ft, linkage, mangled_c.ptr());
    setSection(proto, ".text.startup".ptr());
    if(std::getenv("cxx_global").is_some()){
      handle_cxx_global(proto, path);
    }
    vector_Type_delete(args);
    return Pair::new(proto, mangled);
  }

  func handle_cxx_global(f: Function*, path: str){
    //_GLOBAL__sub_I_glob.cpp
    let args_ft = vector_Type_new();
    let ft = make_ft(getVoidTy(), args_ft, false);
    let linkage = internal();
    let mangled_c = mangle_static(path).cstr();
    let caller_proto = make_func(ft, linkage, mangled_c.ptr());
    setSection(caller_proto, ".text.startup".ptr());
    let bb = create_bb2(caller_proto);
    SetInsertPoint(bb);
    let args = vector_Value_new();
    CreateCall(f, args);
    CreateRetVoid();
    vector_Type_delete(args_ft);
    vector_Value_delete(args);
    mangled_c.drop();
  }

  func do_inline(self, expr: Expr*, ptr_ret: Value*){
    match expr{
      Expr::Call(call*) => {
        let rt = self.get_resolver().visit(expr);
        let method = self.get_resolver().get_method(&rt);
        if(method.is_some()){
          self.visit_call2(expr, call, Option::new(ptr_ret), rt);
          return;
        }
        rt.drop();
      },
      Expr::Type(type*) => {
        self.simple_enum(type, ptr_ret);
      },
      Expr::Obj(type*, args*) => {
        self.visit_obj(expr, type, args, ptr_ret);
      },
      Expr::ArrAccess(aa*) => {
        self.visit_slice(expr, aa, ptr_ret);
      },
      Expr::Lit(lit*) => {
        self.str_lit(lit.val.str(), ptr_ret);
      },
      Expr::Array(list*, sz*) => {
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
    Expr::ArrAccess(aa*) => return aa.idx2.is_some(),//slice creation
    Expr::Lit(lit*) => return lit.kind is LitKind::STR,
    Expr::Type(type*) => return true,
    Expr::Array(elems*, size) => return true,
    Expr::Obj(type*, args*) => return true,
    Expr::Call(call*) => {
      let rt = r.visit(e);
      if(rt.is_method()){
        let target = r.get_method(&rt).unwrap();
        rt.drop();
        return is_struct(&target.type);
      }
      rt.drop();
      return false;
    },
    _ => return false,
  }
}

func getPrimitiveSizeInBits2(val: Value*): i32{
  let ty = Value_getType(val);
  return getPrimitiveSizeInBits(ty);
}

func gep_arr(type: llvm_Type*, ptr: Value*, i1: i32, i2: i32): Value*{
  let args = vector_Value_new();
  vector_Value_push(args, makeInt(i1, 64) as Value*);
  vector_Value_push(args, makeInt(i2, 64) as Value*);
  let res = CreateInBoundsGEP(type, ptr, args);
  vector_Value_delete(args);
  return res;
}

func gep_arr(type: llvm_Type*, ptr: Value*, i1: Value*, i2: Value*): Value*{
  let args = vector_Value_new();
  vector_Value_push(args, i1);
  vector_Value_push(args, i2);
  let res = CreateInBoundsGEP(type, ptr, args);
  vector_Value_delete(args);
  return res;
}

func gep_ptr(type: llvm_Type*, ptr: Value*, i1: Value*): Value*{
  let args = vector_Value_new();
  vector_Value_push(args, i1);
  let res = CreateGEP(type, ptr, args);
  vector_Value_delete(args);
  return res;
}

func get_tag_index(decl: Decl*): i32{
  assert(decl.is_enum());
  return 0;
}

func get_data_index(decl: Decl*): i32{
  assert(decl.is_enum());
  return 1;
}