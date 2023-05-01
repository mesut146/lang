
#derive(Debug)
class Unit{
  path: String;
  last_line: i32;
  imports: List<ImportStmt>;
  items: List<Item>;
}

impl Unit{
  func new(path: String): Self{
    return Self{path.clone(), 0, List<ImportStmt>::new(), List<Item>::new()};
  }
}

#derive(Debug)
class ImportStmt{
  list: List<String>;
}

#derive(Debug)
enum Item{
  Method(m: Method),
  Struct(s: StructDecl)
}

class BaseDecl{
  line: i32;
  unit: Unit*;
  type: Type;
  is_resolved: bool;
  is_generic: bool;
  base: Option<Type>;
  derives: List<Type>;
}

#derive(Debug)
class StructDecl: BaseDecl{
  fields: List<FieldDecl>;
}

#derive(Debug)
class FieldDecl{
  name: String;
  type: Type;
}

#derive(Debug)
class Method{
  line: i32;
  unit: Unit*;
}

//#derive(Debug)
enum Type{
  Simple(scope: Option<Box<Type>>, name: String, args: List<Type>),
  Prim(s: String),
  Pointer(type: Box<Type>),
  Array(type: Box<Type>, size: i32),
  Slice(type: Box<Type>)
}

impl Debug for Type{
  func debug(self, f: Fmt*){
    if let Type::Simple(scp, name, args)=(self){
      if(scp.is_some()){}
      f.print(name);
      if(!args.empty()){
        f.print("<");
        for(let i=0;i<args.len();++i){
          if(i>0) f.print(", ");
          args.get_ptr(i).debug(f);
        }
        f.print(">");
      }
    }
    if let Type::Pointer(ty)=(self){
      ty.get().debug(f);
      f.print("*");
    }
  }
}