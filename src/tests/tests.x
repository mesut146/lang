 import std/map
 import std/io
 import std/fs
 import std/libc
 import std/stack
 import std/regex
 import std/result

 import ast/lexer
 import ast/token
 import ast/parser
 import ast/ast
 import ast/printer
 import ast/utils

 import resolver/resolver

 static root = Option<String>::new();

 func find_root(bin_path: str, cmd: CmdArgs*): String*{
     let tmp = cmd.get_val("-root");
     if(tmp.is_some()){
         root.set(tmp.unwrap());
         return root.get();
     }
     let full = File::resolve(bin_path).unwrap();
     let dir = Path::parent(full.str());
     if(dir.ends_with("build") || dir.ends_with("bin")){
         let res = Path::parent(dir).str();
         full.drop();
         //root = Option::new(res);
         root.set(res);
         return root.get();
     }else if(Path::parent(dir).ends_with("build")){
         let res = Path::parent(Path::parent(dir)).str();
         full.drop();
         //root = Option::new(res);
         root.set(res);
         return root.get();
     }
     full.drop();
     panic("can't find root");
 }

 func get_out(): String{
     File::create_dir(format("{}/build", root.get()).str())?;
     return format("{}/build/test_out", root.get());
 }

 func test_dir(): String{
     return format("{}/tests", root.get());
 }

 func get_src_dir(): String{
     return format("{}/src", root.get());
 }

 func get_std_path(): String{
     return format("{}/src/std", root.get());
 }

func dump(r: Resolver*){
    print("typeMap len={}\n", r.typeMap.len());
    /*for p in &r.typeMap{
        print("typeMap {:?} => {:?}\n", p.a, p.b.type);
    }
    print("---------\n");*/
    //r.typeMap.dump();
}

func handle_resolve(path: String*){
	let ctx = Context::new(get_out(), Option::new(get_src_dir()));
    let r = ctx.create_resolver(path);
    ctx.add_path(get_src_dir().str());
    print("resolving {}\n", path);
    let beg = gettime();
    r.resolve_all();
    let end = gettime();
    let ms = end.sub(&beg);
    print("resolve done {} in {} ms\n", path, ms.as_ms());
    dump(r);
    ctx.drop();
}

func main(argc: i32, args: i8**){
 	let cmd = CmdArgs::new(argc, args);
     if(!cmd.has()){
        print("enter a command\n");
        return;
     }
     find_root(CmdArgs::get_root(), &cmd);
     if(cmd.is("p")){
         //parse test
         cmd.consume();
         print_cst = cmd.consume_any("-cst");
         print("cst={}\n", print_cst);
         let path = cmd.get()?;
         let parser = Parser::from_path(path);
         let unit = parser.parse_unit();
         print("parse done {}\nunit={:?}\n", parser.path(), unit);
         parser.drop();
         unit.drop();
     }else if(cmd.is("r")){
         //resolver test
         cmd.consume();
         let path = cmd.get()?;
         if(File::is_dir(path.str())){
           for fname in File::read_dir(path.str())?{
               let f = format("{}/{}", path, fname);
               if(File::is_dir(f.str())) continue;
               handle_resolve(&f);
               f.drop();
           }
         }else{
           handle_resolve(&path);
         }
         path.drop();
     }else{
     	panic("invalid test command {:?}", cmd.args);
     }
}
