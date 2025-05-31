import std/map
import std/libc
import std/stack

import ast/ast
import ast/utils
import ast/printer
import parser/resolver

struct DropHelper {
  r: Resolver*;
}

impl DropHelper{
  func new(r: Resolver*): DropHelper{
    return DropHelper{r};
  }
  //todo cache drop types
  
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
    match &rt.type{
      Type::Array(elem, size)=>{
        return self.is_drop_type(elem.get());
      },
      Type::Tuple(tt) => {
        for elem in &tt.types{
          if(self.is_drop_type(elem)){
            return true;
          }
        }
        return false;
      },
      _ => {

      }
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
    match decl{
      Decl::Struct(fields)=>{
        for(let i = 0;i < fields.len();++i){
          let fd = fields.get(i);
          if(self.is_drop_type(&fd.type)){
            return true;
          }
        }
      },
      Decl::Enum(variants)=> {
        for(let i = 0;i < variants.len();++i){
          let variant = variants.get(i);
          let fields = &variant.fields;
          for(let j = 0;j < fields.len();++j){
            let fd = fields.get(j);
            if(self.is_drop_type(&fd.type)){
              return true;
            }
          }
        }
      },
      Decl::TupleStruct(fields)=>{
        for fd in fields{
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
      let it: Item* = r.unit.items.get(i);
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
      let it: Item* = r.unit.items.get(i);
      if(!(it is Item::Impl)){
        continue;
      }
      let imp: Impl* = it.as_impl();
      if (is_drop_impl(decl, imp)) {
        return imp;
      }
    }
    panic("no drop method for {:?} self.r={} r={} decl.path={}", decl.type, self.r.unit.path, r.unit.path, decl.path);
  }

  func get_drop_method(self, rt: RType*): Method*{
    //let expr = parse_expr("");
    //self.r.visit(expr);
    let decl = self.r.get_decl(rt).unwrap();
    let drop_impl = self.find_drop_impl(decl);
    if(drop_impl.info.type_params.empty()){
      return drop_impl.methods.get(0);
    }
    let key = rt.type.print();
    let method_desc = self.r.drop_map.get(&key).unwrap();
    key.drop();
    //panic("{} -> {}", rt);
    return self.r.get_method(method_desc, &decl.type).unwrap();
  }
}
