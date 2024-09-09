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
import parser/own_model
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
    compile_dir2(dir, args, exc, Option<String>::new());
}
func compile_dir2(dir: str, args: str, exc: Option<str>, inc: Option<String>){
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
      if(is_dir(file.str())){
        file.drop();
        continue;
      }
      let config = CompilerConfig::new(get_src_dir());
      config.set_file(file);
      config.set_out(get_out());
      config.add_dir(get_src_dir());
      config.set_link(LinkType::Binary{"a.out".str(), args.owned(), true});
      if(inc.is_some()){
        config.add_dir(inc.get().clone());
      }
      config.root_dir.set(root.get().clone());
      let bin = Compiler::compile_single(config);
      bin.drop();
    }
    list.drop();
    inc.drop();
}

func std_test(){
    print("std_test\n");
    let std_dir = get_std_path();
    let out = get_out();
    let lib = build_std(std_dir.str(), out.str(), false);
    let dir = format("{}/tests/std_test", root.get());
    let args = format("{} -lm", &lib);
    compile_dir2(dir.str(), args.str());
    std_dir.drop();
    out.drop();
    lib.drop();
    dir.drop();
    args.drop();
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
    let args = format("{} -lm", &lib);
    compile_dir2(dir.str(), args.str());
    lib.drop();
    dir.drop();
    args.drop();
}

func own_test(id: i32){
    print("test::own_test\n");
    drop_enabled = true;
    let config = CompilerConfig::new(get_src_dir());
    let out = get_out();
    let std_dir = get_std_path();
    config
      .set_file(format("{}/tests/own/common.x" , root.get()))
      .set_out(out.clone())
      .add_dir(test_dir())
      .add_dir(get_src_dir())
      .set_link(LinkType::Static{"common.a".str()});

    let common_lib = Compiler::compile_single(config);
    let stdlib = build_std(std_dir.str(), out.str());
    
    let args = format("{} {}", &common_lib, &stdlib);
    if(id == 1){
        let dir = format("{}/tests/own", root.get());
        compile_dir2(dir.str(), args.str(), Option::new("common.x"), Option::new(test_dir()));
        dir.drop();
    }else{
        let dir = format("{}/tests/own_if", root.get());
        compile_dir2(dir.str(), args.str(), Option::new("common.x"), Option::new(test_dir()));
        dir.drop();
    }
    args.drop();
    out.drop();
    common_lib.drop();
    stdlib.drop();
    std_dir.drop();
    drop_enabled = false;
}

func handle_tests(cmd: CmdArgs*): bool{
    print("root={}\n", find_root(cmd.get_root()));
    if(cmd.is("own")){
        own_test(1);
        return true;
    }
    if(cmd.is("own2")){
        own_test(2);
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
        print_cst = cmd.consume_any("-cst");
        print("cst={}\n", print_cst);
        let path = cmd.get();
        let parser = Parser::from_path(path);
        let unit = parser.parse_unit();
        print("parse done {}\nunit={}\n", parser.path, unit);
        parser.drop();
        unit.drop();
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