// import std/map
// import std/io
// import std/fs
// import std/libc
// import std/stack
// import std/regex
// import std/result

// import ast/lexer
// import ast/token
// import ast/parser
// import ast/ast
// import ast/printer
// import ast/utils

// import parser/resolver
// import parser/compiler
// import parser/debug_helper
// import parser/llvm
// import parser/ownership
// import parser/own_model
// import parser/cache
// import parser/main

// static root = Option<String>::new();

// func find_root(bin_path: str): String*{
//     let full = File::resolve(bin_path).unwrap();
//     let dir = Path::parent(full.str());
//     if(dir.ends_with("build") || dir.ends_with("bin")){
//         let res = Path::parent(dir).str();
//         full.drop();
//         //root = Option::new(res);
//         root.set(res);
//         return root.get();
//     }else if(Path::parent(dir).ends_with("build")){
//         let res = Path::parent(Path::parent(dir)).str();
//         full.drop();
//         //root = Option::new(res);
//         root.set(res);
//         return root.get();
//     }
//     full.drop();
//     panic("can't find root");
// }

// /*func get_build(): String{
//     return format("{}/build", root.get());
// }*/

// func get_out(): String{
//     File::create_dir(format("{}/build", root.get()).str());
//     return format("{}/build/test_out", root.get());
// }

// func test_dir(): String{
//     return format("{}/tests", root.get());
// }

// func get_src_dir(): String{
//     return format("{}/src", root.get());
// }

// func get_std_path(): String{
//     return format("{}/src/std", root.get());
// }


// func compile_dir2(dir: str, args: str){
//     compile_dir2(dir, args, Option<str>::new());
// }
// func compile_dir2(dir: str, args: str, exc: Option<str>){
//     compile_dir2(dir, args, exc, Option<String>::new());
// }
// func compile_dir2(dir: str, args: str, exc: Option<str>, inc: Option<String>){
//     let list: List<String> = File::read_dir(dir).unwrap();
//     list.sort();
//     print("compile_dir '{}' -> {} elems\n", dir, list.len());
//     for(let i = 0;i < list.len();++i){
//       let name: String* = list.get(i);
//       if(!name.str().ends_with(".x")) continue;
//       if(exc.is_some() && name.eq(*exc.get())){
//         continue;
//       }
//       let file: String = dir.str();
//       file.append("/");
//       file.append(name);
//       if(File::is_dir(file.str())){
//         file.drop();
//         continue;
//       }
//       let config = CompilerConfig::new(get_src_dir());
//       config.set_file(file);
//       config.set_out(get_out());
//       config.add_dir(get_src_dir());
//       config.set_link(LinkType::Binary{"a.out".str(), args.owned(), true});
//       if(inc.is_some()){
//         config.add_dir(inc.get().clone());
//       }
//       config.root_dir.set(root.get().clone());
//       let bin = Compiler::compile_single(config)?;
//       bin.drop();
//     }
//     list.drop();
//     inc.drop();
// }

// func normal_test_dir(pat: String, incremental: bool){
//     let dir = format("{}/{}", test_dir(), pat);
//     let config = CompilerConfig::new(get_src_dir());
//     config.set_file(dir);
//     config.set_out(get_out());
//     config.root_dir.set(root.get().clone());
//     config.add_dir(get_src_dir());
//     config.add_dir(test_dir());
//     config.set_link(LinkType::Binary{"a.out".str(), "".owned(), true});
//     config.incremental_enabled = incremental;
//     print("inc={}\n", incremental);
//     Compiler::compile_dir(config)?;
// }

// func own_test(id: i32){
//     print("test::own_test\n");
//     drop_enabled = true;
//     let config = CompilerConfig::new(get_src_dir());
//     let out = get_out();
//     let std_dir = get_std_path();
//     config
//       .set_file(format("{}/tests/own/common.x" , root.get()))
//       .set_out(out.clone())
//       .add_dir(test_dir())
//       .add_dir(get_src_dir())
//       .set_link(LinkType::Static{"common.a".str()});

//     let common_lib = Compiler::compile_single(config)?;
//     let stdlib = build_std(std_dir.str(), out.str());
    
//     let args = format("{} {}", &common_lib, &stdlib);
//     if(id == 1){
//         let dir = format("{}/tests/own", root.get());
//         compile_dir2(dir.str(), args.str(), Option::new("common.x"), Option::new(test_dir()));
//         dir.drop();
//     }else{
//         let dir = format("{}/tests/own_if", root.get());
//         compile_dir2(dir.str(), args.str(), Option::new("common.x"), Option::new(test_dir()));
//         dir.drop();
//     }
//     args.drop();
//     out.drop();
//     common_lib.drop();
//     stdlib.drop();
//     std_dir.drop();
//     drop_enabled = false;
// }

// func handle_tests(cmd: CmdArgs*): bool{
//     find_root(CmdArgs::get_root());
//     if(cmd.is("own")){
//         own_test(1);
//         return true;
//     }
//     if(cmd.is("own2")){
//         own_test(2);
//         return true;
//     }
//     else if(cmd.is("testd")){
//         cmd.consume();
//         let inc = cmd.consume_any("-inc");
//         let path = cmd.get()?;
//         normal_test_dir(path, inc);
//         cmd.end();
//         return true;
//     }
//     else if(cmd.is("p")){
//         //parse test
//         cmd.consume();
//         print_cst = cmd.consume_any("-cst");
//         print("cst={}\n", print_cst);
//         let path = cmd.get()?;
//         let parser = Parser::from_path(path);
//         let unit = parser.parse_unit();
//         print("parse done {}\nunit={:?}\n", parser.path(), unit);
//         parser.drop();
//         unit.drop();
//         return true;
//     }else if(cmd.is("r")){
//         //resolver test
//         cmd.consume();
//         let path = cmd.get()?;
//         let ctx = Context::new(get_out(), Option::new(get_std_path()));
//         let resolver = ctx.create_resolver(&path);
//         print("resolve done {}\n", path);
//         ctx.drop();
//         path.drop();
//         return true;
//     }
//     return false;
// }