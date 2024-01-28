import parser/resolver
import parser/ast
import parser/printer
import parser/utils
import parser/copier
import parser/bridge
import parser/compiler_helper
import std/map
import std/io

struct Compiler{
  ctx: Context;
  config: Config;
  resolver: Resolver*;
  main_file: Option<String>;
  llvm: llvm_holder;
}

struct Protos{
  sliceType: StructType*;
}

struct llvm_holder{
  target_machine: TargetMachine*;
  target_triple: String;
}

struct Config{
  verbose: bool;
  single_mode: bool;
}

func dummy_resolver(ctx: Context*): Resolver*{
  let path = "../tests/src/std/str.x".str();
  return ctx.create_resolver(&path);
}

func is_main(m: Method*): bool{
  return m.name.eq("main") && m.params.empty();
}

func has_main(unit: Unit*): bool{
  for (let i=0;i<unit.items.len();++i) {
    let it = unit.items.get_ptr(i);
    if let Item::Method(m*)=(it){
      if(is_main(m)){
        return true;
      }
    }
  }
  return false;
}

func get_out_file(path: str): String{
  let name = getName(path);
  let noext = trimExtenstion(name).str();
  noext.append(".o");
  return noext;
}

func trimExtenstion(name: str): str{
  let i = name.lastIndexOf(".");
  return name.substr(0, i);
}

func getName(path: str): str{
  let i = path.lastIndexOf("/");
  return path.substr(i + 1);
}

impl Compiler{
  func new(ctx: Context): Compiler{
    return Compiler{ctx: ctx, config: Config{verbose: true, single_mode: false},
     resolver: dummy_resolver(&ctx), main_file: Option<String>::new(),
    llvm: Compiler::init()};
  }

  func unit(self): Unit*{
    return &self.resolver.unit;
  }

  func compile(self, path0: str): String{
    //print("compile %s\n", path0.cstr());
    let path = Path::new(path0.str());
    let outFile = get_out_file(path0);
    let ext = path.ext();
    if (!ext.eq("x")) {
      panic("invalid extension %s", ext.cstr());
    }
    if(self.config.verbose){
      print("compiling %s\n", path0.cstr());
    }
    self.resolver = self.ctx.create_resolver(path0);
    if (has_main(self.unit())) {
      self.main_file = Option::new(path0.str());
      if (!self.config.single_mode) {//compile last
          return outFile;
      }
    }
    self.resolver.resolve_all();
    self.initModule(path0);
    self.createProtos();
    panic("");
  }

  //make all struct decl & method decl used by this module
  func createProtos(self){
    let sliceType = make_slice_type();
    make_string_type(sliceType as llvm_Type*);

    let list = List<Decl*>::new();
    getTypes(self.unit(), &list);
    for (let i=0;i<self.resolver.used_types.len();++i) {
      let decl = self.resolver.used_types.get(i);
      if (decl.is_generic) {
          //error("gen");
          continue;
      }
      list.add(decl);
    }
  }

  func initModule(self, path: str){
    let name = getName(path);
    make_ctx();
    make_module(name.cstr(), self.llvm.target_machine, self.llvm.target_triple.cstr());
    make_builder();
    //c->init_dbg(path);
  }

  func init(): llvm_holder{
    InitializeAllTargetInfos();
    InitializeAllTargets();
    InitializeAllTargetMCs();
    InitializeAllAsmParsers();
    InitializeAllAsmPrinters();
    
    let target_triple = getDefaultTargetTriple2();
    let target_machine = createTargetMachine(target_triple.cstr());
    return llvm_holder{target_triple: target_triple, target_machine: target_machine};

    //todo cache
  }
}