import parser/lexer
import parser/token
import parser/parser
import parser/ast
import parser/printer
import parser/resolver
import parser/compiler
import parser/debug_helper
import parser/bridge
import parser/utils
import parser/ownership
import parser/cache
import parser/main
import std/map
import std/io
import std/libc
import std/stack

static root = Option<String>::new();

func find_root(bin_path: str): String*{
    let full = resolve(bin_path);
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

func root(): str{
    panic("");
}

func get_build(): String{
    return format("{}/build", root.get());
}

func get_out(): String{
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


func compile_dir2(dir: str, args: str){
    compile_dir2(dir, args, Option<str>::new());
}
  
func compile_dir2(dir: str, args: str, exc: Option<str>){
    let list: List<String> = list(dir);
    list.sort();
    print("compile_dir '{}' -> {} elems\n", dir, list.len());
    for(let i = 0;i < list.len();++i){
      let name: String* = list.get_ptr(i);
      if(!name.str().ends_with(".x")) continue;
      if(exc.is_some() && name.eq(*exc.get())){
        continue;
      }
      let file: String = dir.str();
      file.append("/");
      file.append(name);
      if(is_dir(file.str())) continue;
      let config = CompilerConfig::new(get_src_dir());
      config
        .set_file(file)
        .set_out(get_out())
        .add_dir(get_src_dir())
        .set_link(LinkType::Binary{"a.out", args, true});
      config.root_dir.set(root.get().clone());
      let bin = Compiler::compile_single(config);
      bin.drop();
    }
    list.drop();
}

func std_test(){
    print("std_test\n");
    let std_dir = get_std_path();
    let out = get_out();
    let lib = build_std(std_dir.str(), out.str());
    let dir = format("{}/tests/std_test", root.get());
    compile_dir2(dir.str(), lib.str());
    std_dir.drop();
    out.drop();
    lib.drop();
    dir.drop();
}

func normal_test(){
    print("normal_test\n");
    let rt_src = format("{}/src/std/rt.x", root.get());
    let config = CompilerConfig::new(get_src_dir());
    config
    .set_file(rt_src)
    .set_out(get_out())
    .add_dir(get_src_dir())
    .set_link(LinkType::Static{"rt.a".str()});
    config.root_dir.set(root.get().clone());
    let lib = Compiler::compile_single(config);
    let dir = format("{}/tests/normal", root.get());
    compile_dir2(dir.str(), lib.str());
    lib.drop();
    dir.drop();
}

func own_test(id: i32, std_dir: str){
    print("test::own_test\n");
    drop_enabled = true;
    let config = CompilerConfig::new(get_src_dir());
    let out = get_out();
    config
      .set_file("../tests/own/common.x")
      .set_out(out.clone())
      .add_dir(root())
      .set_link(LinkType::Static{"common.a".str()});
    let bin = Compiler::compile_single(config);
    bin.drop();
  
    let lib = build_std(std_dir, out.str());
    lib.drop();
  
    let args = format("{}/common.a {}/std.a", &out, &out);
    if(id == 1){
      compile_dir2("../tests/own", args.str(), Option::new("common.x"));
    }else{
      compile_dir2("../tests/own_if", args.str(), Option::new("common.x"));
    }
    args.drop();
    out.drop();
    drop_enabled = false;
}

func handle_tests(cmd: CmdArgs*): bool{
    print("root={}\n", find_root(cmd.get_root()));
    if(cmd.is("own")){
        //own_test(1);
        return true;
    }
    if(cmd.is("own2")){
        //own_test(2);
        return true;
    }
    if(cmd.is("test")){
        normal_test();
        return true;
    }
    else if(cmd.is("test2")){
        std_test();
        return true;
    }else if(cmd.is("p")){
        //parse test
        cmd.consume();
        let path = cmd.get();
        let parser = Parser::from_path(path);
        print("parse done {}\n", parser.path);
        parser.drop();
        return true;
    }else if(cmd.is("r")){
        //resolver test
        cmd.consume();
        let path = cmd.get();
        let ctx = Context::new(get_out(), Option::new(get_std_path()));
        let resolver = ctx.create_resolver(&path);
        print("resolve done {}\n", path);
        ctx.drop();
        path.drop();
        return true;
    }
    return false;
}