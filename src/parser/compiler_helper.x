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
        return mc.args.get_ptr(0);
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

struct DropHelper {
  r: Resolver*;
}

impl DropHelper{
  func new(r: Resolver*): DropHelper{
    return DropHelper{r};
  }
  func is_drop_type(self, expr: Expr*): bool{
    let rt = self.r.visit(expr);
    let res = self.is_drop_type(&rt);
    rt.drop();
    return res;
  }
  func is_drop_type(self, type: Type*): bool{
    if (type.is_str() || type.is_slice()) return false;
    if (!is_struct(type)) return false;
    if (type.is_array()) {
        let elem = type.elem();
        return self.is_drop_type(elem);
    }
    let rt = self.r.visit_type(type);
    let res = self.is_drop_type(&rt);
    rt.drop();
    return res;
  }
  func is_drop_type(self, rt: RType*): bool{
    let type = &rt.type;
    if (type.is_str() || type.is_slice()) return false;
    if (!is_struct(type)) return false;
    if (type.is_array()) {
        let elem = type.elem();
        return self.is_drop_type(elem);
    }
    let decl = self.r.get_decl(rt).unwrap();
    return self.is_drop_decl(decl);
  }
  func is_drop_decl(self, decl: Decl*): bool{
    if(decl.is_drop()) return true;
    if(decl.base.is_some()){
      if(self.is_drop_type(decl.base.get())){
        return true;
      }
    }
    if(decl.is_struct()){
      let fields = decl.get_fields();
      for(let i = 0;i < fields.len();++i){
        let fd = fields.get_ptr(i);
        if(self.is_drop_type(&fd.type)){
          return true;
        }
      }
    }else{
      let vars = decl.get_variants();
      for(let i = 0;i < vars.len();++i){
        let variant = vars.get_ptr(i);
        let fields = &variant.fields;
        for(let j = 0;j < fields.len();++j){
          let fd = fields.get_ptr(j);
          if(self.is_drop_type(&fd.type)){
            return true;
          }
        }
      }
    }
    return false;
  }
  func is_drop_impl(decl: Decl*, imp: Impl*): bool{
    let info = &imp.info;
    //print("is_drop_impl {} {}\n", decl.type, info);
    if (info.trait_name.is_none() || !info.trait_name.get().eq("Drop")) return false;
    if (decl.is_generic) {
        if (!info.type_params.empty()) {//generic impl
          return decl.type.name().eq(info.type.name());
        } else {//full impl
          //different impl of type param
          return false;
        }
    } else {                           //full type
        if (info.type_params.empty()) {//full impl
          let res = decl.type.eq(&info.type);
          return res;
        } else {//generic impl
          return decl.type.name().eq(info.type.name());
        }
    }
  }
  func has_drop_impl(decl: Decl*, r: Resolver*): bool{
    if (!decl.path.eq(&r.unit.path)) {
        //need own resolver
        let r2 = r.ctx.create_resolver(&decl.path);
        r2.init();
        r = r2;
    }
    for (let i = 0;i < r.unit.items.len();++i) {
      let it: Item* = r.unit.items.get_ptr(i);
      if(!(it is Item::Impl)){
        continue;
      }
      let imp: Impl* = it.as_impl();
      if (is_drop_impl(decl, imp)) {
        return true;
      }
    }
    return false;
  }
  func find_drop_impl(self, decl: Decl*): Impl*{
    let r = self.r;
    if (!decl.path.eq(&r.unit.path)) {
      //need own resolver
      let r2 = r.ctx.create_resolver(&decl.path);
      r2.init();
      r = r2;
    }
    for (let i = 0;i < r.unit.items.len();++i) {
      let it: Item* = r.unit.items.get_ptr(i);
      if(!(it is Item::Impl)){
        continue;
      }
      let imp: Impl* = it.as_impl();
      if (is_drop_impl(decl, imp)) {
        return imp;
      }
    }
    panic("no drop method for {} self.r={} r={} decl.path={}", decl.type, self.r.unit.path, r.unit.path, decl.path);
  }

  func get_drop_method(self, rt: RType*): Method*{
    //let expr = parse_expr("");
    //self.r.visit(expr);
    let decl = self.r.get_decl(rt).unwrap();
    let drop_impl = self.find_drop_impl(decl);
    if(drop_impl.info.type_params.empty()){
      return drop_impl.methods.get_ptr(0);
    }
    let key = rt.type.print();
    let method_desc = self.r.drop_map.get_ptr(&key).unwrap();
    key.drop();
    //panic("{} -> {}", rt);
    return self.r.get_method(method_desc, &decl.type).unwrap();
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

/*func make_string_type(sliceType: llvm_Type*): StructType*{
    let elems = vector_Type_new();
    vector_Type_push(elems, sliceType);
    let res = make_struct_ty2("str".ptr(), elems);
    vector_Type_delete(elems);
    return res;
}*/

func make_printf(): Function*{
    let args = vector_Type_new();
    vector_Type_push(args, getPointerTo(getInt(8)) as llvm_Type*);
    let ft = make_ft(getInt(32), args, true);
    let f = make_func(ft, ext(), "printf".ptr());
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
        let item = unit.items.get_ptr(i);
        if let Item::Decl(d*)=(item){
            if(d.is_generic) continue;
            list.add(d);
        }
    }
}

func sort(list: List<Decl*>*, r: Resolver*){
  for (let i = 0; i < list.len(); ++i) {
    //find decl belongs to i'th index
    let min: Decl* = *list.get_ptr(i);
    for (let j = i + 1; j < list.len(); ++j) {
      let cur: Decl* = *list.get_ptr(j);
      if (r.is_cyclic(&min.type, &cur.type)) {
        min = cur;
        swap(list, i, j);
      }
    }
  }
}

func all_deps(decl: Decl*, r: Resolver*, res: List<String>*){
  if(decl.is_struct()){
    let fields = decl.get_fields();
    for (let j = 0; j < fields.len(); ++j) {
      let fd = fields.get_ptr(j);
      res.add_not_exist(fd.type.print());
      all_deps(&fd.type, r, res);
    }
  }else{
    let variants = decl.get_variants();
    for (let j = 0; j < variants.len(); ++j) {
      let ev = variants.get_ptr(j);
      for (let k = 0; k < ev.fields.len(); ++k) {
        let fd = ev.fields.get_ptr(k);
        res.add_not_exist(fd.type.print());
        all_deps(&fd.type, r, res);
      }
    }
  }
}
func all_deps(type: Type*, r: Resolver*, res: List<String>*){
  if(type.is_pointer()) return;
  let rt = r.visit_type(type);
  let opt = r.get_decl(&rt);
  if(opt.is_none()){
    rt.drop();
    return;
  }
  let decl = opt.unwrap();
  all_deps(decl, r, res);
  rt.drop();
}

func sort2(list: List<Decl*>*, r: Resolver*){
  //parent -> fields
  let map = Map<String, List<String>>::new();
  for (let i = 0; i < list.len(); ++i) {
    let decl = *list.get_ptr(i);
    let arr = List<String>::new();
    all_deps(decl, r, &arr);
    map.add(decl.type.print(), arr);
  }
  for (let i = 0; i < list.len(); ++i) {
    //find decl belongs to i'th index
    for (let j = 0; j < list.len() - 1; ++j) {
      let d1: Decl* = *list.get_ptr(j);
      let d2: Decl* = *list.get_ptr(j + 1);
      //if d1 is parent of d2, swap
      let s1 = d1.type.print();
      let s2 = d2.type.print();
      let chs = map.get_ptr(&s1).unwrap();
      if(chs.contains(&s2)){
        swap(list, j, j + 1);
      }
      s2.drop();
    }
  }
  map.drop();
}

/*func sort3(list: List<Decl*>*, r: Resolver*){
  //parent -> fields
  let map = Map<String, List<String>>::new();
  //ch -> parents
  let map2 = Map<String, List<String>>::new();
  for (let i = 0; i < list.len(); ++i) {
    let decl = *list.get_ptr(i);
    let tstr = decl.type.print();
    if(!map.contains(&tstr)){
      map.add(tstr.clone(), List<String>::new());
    }
    let deps_arr = map.get_ptr(&tstr).unwrap();
    if(decl.is_struct()){
      let fields = decl.get_fields();
      for (let j = 0; j < fields.len(); ++j) {
        let fd = fields.get_ptr(j);
        let field_str = fd.type.print();
        deps_arr.add(field_str.clone());
        let parents = &map2.get_pair_or(field_str.clone(), List<String>::new()).b;
        parents.add(tstr.clone());
        //find parent of decl & merge children
        let p_arr = map2.get_ptr(&tstr).unwrap();
        for parent in p_arr{
          //let other_ch_arr = map.get_pair_or(parent);
        }
        field_str.drop();
      }
    }else{
      let variants = decl.get_variants();
      for (let j = 0; j < variants.len(); ++j) {
        let ev = variants.get_ptr(j);
        for (let k = 0; k < ev.fields.len(); ++k) {
          let fd = ev.fields.get_ptr(k);
          deps_arr.add(fd.type.print());
          
        }
      }
    }
    tstr.drop();
  }
  for (let i = 0; i < list.len(); ++i) {
    //find decl belongs to i'th index
    for (let j = 0; j < list.len() - 1; ++j) {
      let d1: Decl* = *list.get_ptr(j);
      let d2: Decl* = *list.get_ptr(j + 1);
      //is d1 is parent of d2, swap
      let s1 = d1.type.print();
      let s2 = d2.type.print();
      let chs = map.get_ptr(&s2).unwrap();
      if(chs.contains(&s1)){
        swap(list, j, j + 1);
      }
      s2.drop();
    }
  }
  map.drop();
}*/

func swap(list: List<Decl*>*, i: i32, j: i32){
  let a = *list.get_ptr(i);
  let b = *list.get_ptr(j);
  list.set(j, a);
  list.set(i, b);
}

func getMethods(unit: Unit*): List<Method*>{
  let list = List<Method*>::new(100);
  for (let i = 0;i < unit.items.len();++i) {
    let item = unit.items.get_ptr(i);
    if let Item::Method(m*)=(item){
        if(m.is_generic) continue;
        list.add(m);
    }else if let Item::Impl(imp*)=(item){
      if(!imp.info.type_params.empty()) continue;
      for(let j = 0;j < imp.methods.len();++j){
        list.add(imp.methods.get_ptr(j));
      }
    }else if let Item::Extern(methods*)=(item){
      for(let j = 0;j < methods.len();++j){
        list.add(methods.get_ptr(j));
      }
    }
  }
  //broken after expand, ptr
  return list;
}

impl Compiler{
  func get_global_string(self, val: String): Value*{
    let opt = self.string_map.get_ptr(&val);
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
    let p = self.protos.get();
    /*if(s.eq("str")){
      return p.std("str") as llvm_Type*;
    }*/
    if(type.is_void()) return getVoidTy();
    let prim_size = prim_size(s.str());
    if(prim_size.is_some()){
      return getInt(prim_size.unwrap());
    }
    if let Type::Array(elem*,size)=(type){
      let elem_ty = self.mapType(elem.get());
      return getArrTy(elem_ty, size) as llvm_Type*;
    }
    if let Type::Slice(elem*)=(type){
      return p.std("slice") as llvm_Type*;
    }
    if let Type::Pointer(elem*)=(type){
      let elem_ty = self.mapType(elem.get());
      return getPointerTo(elem_ty) as llvm_Type*;
    }
    if(!p.classMap.contains(s)){
      panic("mapType {}\n", s);
    }
    return p.get(s);
  }

  //normal decl protos and di protos
  func make_decl_protos(self){
    let p = self.protos.get();
    let list = List<Decl*>::new();
    getTypes(self.unit(), &list);
    for (let i = 0;i < self.get_resolver().used_types.len();++i) {
      let rt = self.get_resolver().used_types.get_ptr(i);
      let decl = self.get_resolver().get_decl(rt).unwrap();
      if (decl.is_generic) continue;
      list.add(decl);
    }
    sort2(&list, self.get_resolver());
    //first create just protos to fill later
    for(let i = 0;i < list.len();++i){
      let decl = *list.get_ptr(i);
      self.make_decl_proto(decl);
    }
    //fill with elems
    for(let i = 0;i < list.len();++i){
      let decl = *list.get_ptr(i);
      self.fill_decl(decl, p.get(decl) as StructType*);
    }
    if(self.llvm.di.get().debug){
      //di proto
      for(let i = 0;i < list.len();++i){
        let decl = *list.get_ptr(i);
        self.llvm.di.get().map_di_proto(decl, self);
      }
      //di fill
      for(let i = 0;i < list.len();++i){
        let decl = *list.get_ptr(i);
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
        let ev = vars.get_ptr(i);
        let name = format("{}::{}", decl.type, ev.name);
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
    if let Decl::Enum(variants*)=(decl){
      //calc enum size
      let max = 0;
      for(let i = 0;i < variants.len();++i){
        let ev = variants.get_ptr(i);
        let name = format("{}::{}", decl.type, ev.name.str());
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
    }else if let Decl::Struct(fields*)=(decl){
      if(decl.base.is_some()){
        vector_Type_push(elems, self.mapType(decl.base.get()));
      }
      for(let i = 0;i < fields.len();++i){
        let fd = fields.get_ptr(i);
        let ft = self.mapType(&fd.type);
        vector_Type_push(elems, ft);
      }
    }
    setBody(st, elems);
    vector_Type_delete(elems);
    //print("fill_decl {}\n", &decl.type);
    //Type_dump(st as llvm_Type*);
    let size = getSizeInBits(st);
    if(size == 0){
      print("sizeof {}={}\n", &decl.type, size);
    }
  }
  func make_variant_type(self, ev: Variant*, decl: Decl*, name: String*, ty: StructType*){
    let elems = vector_Type_new();
    if(decl.base.is_some()){
      vector_Type_push(elems, self.mapType(decl.base.get()));
    }
    for(let j = 0;j < ev.fields.len();++j){
      let fd = ev.fields.get_ptr(j);
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
    let rvo = is_struct(&m.type);
    let ret = getVoidTy();
    if(is_main(m)){
      ret = getInt(32);
    }else if(!rvo){
      ret = self.mapType(&m.type);
    }
    let args = vector_Type_new();
    if(rvo){
      let rvo_ty = getPointerTo(self.mapType(&m.type)) as llvm_Type*;
      vector_Type_push(args, rvo_ty);
    }
    if(m.self.is_some()){
      let self_ty = self.mapType(&m.self.get().type);
      if(is_struct(&m.self.get().type)){
        self_ty = getPointerTo(self_ty) as llvm_Type*;
      }
      vector_Type_push(args, self_ty);
    }
    for(let i = 0;i < m.params.len();++i){
      let prm = m.params.get_ptr(i);
      let pt = self.mapType(&prm.type);
      if(is_struct(&prm.type)){
        pt = getPointerTo(pt) as llvm_Type*;
      }
      vector_Type_push(args, pt);
    }
    let ft = make_ft(ret, args, false);
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
    mangled_c.drop();
    if(rvo){
      let arg = get_arg(f, 0);
      Argument_setname(arg, "ret".ptr());
      Argument_setsret(arg, self.mapType(&m.type));
    }
    self.protos.get().funcMap.add(mangled, f);
    vector_Type_delete(args);
    return Option::new(f);
  }

  func getSize(self, type: Type*): i64{
    if(type.is_prim()){
      return prim_size(type.name().str()).unwrap();
    }
    if(type.is_pointer()) return 64;
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
    panic("getSize {}", type);
  }

  func getSize(self, decl: Decl*): i64{
    let mapped = self.mapType(&decl.type);
    return getSizeInBits(mapped as StructType*);
  }

  func cast(self, expr: Expr*, target_type: Type*): Value*{
    let val = self.loadPrim(expr);
    let val_ty = Value_getType(val);
    let src = getPrimitiveSizeInBits(val_ty);
    let trg_size = self.getSize(target_type);
    let trg_ty = getInt(trg_size as i32);
    if(src < trg_size){
      let src_type = self.get_resolver().getType(expr);
      if(isUnsigned(&src_type)){
        src_type.drop();
        return CreateZExt(val, trg_ty);
      }else{
        src_type.drop();
        return CreateSExt(val, trg_ty);
      }
    }else if(src > trg_size){
      return CreateTrunc(val, trg_ty);
    }
    return val;
  }

  func loadPrim(self, expr: Expr*): Value*{
    let val = self.visit(expr);
    let ty = Value_getType(val);
    if(!isPointerTy(ty)) return val;
    let type = self.getType(expr);
    let res = CreateLoad(self.mapType(&type), val);//local var
    type.drop();
    return res;
  }

  func setField(self, expr: Expr*, type: Type*, trg: Value*){
    self.setField(expr, type, trg, Option<Expr*>::new());
  }
  
  func setField(self, expr: Expr*, type: Type*, trg: Value*, lhs: Option<Expr*>){
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
    }else if(type.is_pointer()){
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
    if(node is Expr::Obj || node is Expr::Call|| node is Expr::Lit || node is Expr::Unary || node is Expr::As || node is Expr::Infix){
      return val;
    }
    if(node is Expr::Name || node is Expr::ArrAccess || node is Expr::Access){
      let ty = self.getType(node);
      if(ty.is_pointer()){
        ty.drop();
        return CreateLoad(getPtr(), val);
      }
      ty.drop();
      return val;
    }
    panic("get_obj_ptr {}", node);
  }

  func getTag(self, expr: Expr*): Value*{
    let rt = self.get_resolver().visit(expr);
    let decl = self.get_resolver().get_decl(&rt).unwrap();
    let tag_idx = get_tag_index(decl);
    let tag = self.get_obj_ptr(expr);
    let mapped = self.mapType(rt.type.get_ptr());
    rt.drop();
    tag = self.gep2(tag, tag_idx, mapped);
    return CreateLoad(getInt(ENUM_TAG_BITS()), tag);
  }

  func get_variant_ty(self, decl: Decl*, variant: Variant*): llvm_Type*{
    let name = format("{}::{}", decl.type, variant.name.str());
    let res = *self.protos.get().classMap.get_ptr(&name).unwrap();
    name.drop();
    return res;
  }

  func mangle_unit(path: str): String{
    let s1 = path.replace(".", "_");
    let res = s1.replace("/", "_");
    s1.drop();
    return res;
  }

  func mangle_static(path: str): String{
    let mangled = mangle_unit(path);
    let res = format("{}_static_init", mangled);
    mangled.drop();
    return res;
  }

  func make_init_proto(self, path: str): Function*{
    let ret = getVoidTy();
    let args = vector_Type_new();
    let ft = make_ft(ret, args, false);
    let linkage = ext();
    let mangled = mangle_static(path).cstr();
    let res = make_func(ft, linkage, mangled.ptr());
    mangled.drop();
    vector_Type_delete(args);
    return res;
  }

  func do_inline(self, expr: Expr*, ptr_ret: Value*){
    if let Expr::Call(call*)=(expr){
      let rt = self.get_resolver().visit(expr);
      let method = self.get_resolver().get_method(&rt);
      if(method.is_some()){
        self.visit_call2(expr, call, Option::new(ptr_ret), rt);
        return;
      }
      rt.drop();
    }
    if let Expr::Type(type*)=(expr){
      self.simple_enum(type, ptr_ret);
      return;
    }
    if let Expr::Obj(type*, args*)=(expr){
      self.visit_obj(expr, type, args, ptr_ret);
      return;
    }
    if let Expr::ArrAccess(aa*)=(expr){
      self.visit_slice(expr, aa, ptr_ret);
      return;
    }
    if let Expr::Lit(lit*)=(expr){
      self.str_lit(lit.val.str(), ptr_ret);
      return;
    }
    if let Expr::Array(list*, sz*)=(expr){
      self.visit_array(expr, list, sz, ptr_ret);
      return;
    }
    panic("inline {}", expr);
  }
}

func can_inline(expr: Expr*, r: Resolver*): bool{
  return inline_rvo && doesAlloc(expr, r);
}

func doesAlloc(e: Expr*, r: Resolver*): bool{
  if(e is Expr::Obj) return true;
  if let Expr::ArrAccess(aa*)=(e){
    return aa.idx2.is_some();//slice creation
  }
  if let Expr::Lit(lit*)=(e){
    return lit.kind is LitKind::STR;
  }
  if (e is Expr::Type){
    return true;//enum creation
  }
  if (e is Expr::Array){
    return true;
  }
  if let Expr::Call(call*)=(e){
    let rt = r.visit(e);
    if(rt.is_method()){
      let target = r.get_method(&rt).unwrap();
      rt.drop();
      return is_struct(&target.type);
    }
    rt.drop();
    return false;
  }
  return false;
}

func getPrimitiveSizeInBits2(val: Value*): i32{
  let ty = Value_getType(val);
  return getPrimitiveSizeInBits(ty);
}

func gep_arr(type: llvm_Type*, ptr: Value*, i1: i32, i2: i32): Value*{
  let args = vector_Value_new();
  vector_Value_push(args, makeInt(i1, 64));
  vector_Value_push(args, makeInt(i2, 64));
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