import String
import List

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

class ImportStmt{
  list: List<String>;
}

enum Item{
  Method(m: Method)
}

class BaseDecl{
  type: Type;
  isResolved: bool;
  isGeneric: bool;
  base: Type;
  derives: List<Type>;
}

class Method{

}

enum Type{

}