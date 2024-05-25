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
import std/map
import std/io
import std/libc

func root(): str{
  return "../tests";
}
func get_out(): str{
  return "./bt_out";
}

func make_context(): Context{
  let out_dir = get_out();
  create_dir(out_dir);
  return Context::new(root().str(), out_dir.str());
}

func build_std(){
  Compiler::compile_dir("../tests/std", get_out(), root(), "", LinkType::Static{"std.a"});
}

func compile_dir(cmp: Compiler*, dir: CStr, link: bool){
  compile_dir(cmp, dir, link, "");
}

func compile_dir(cmp: Compiler*, dir: CStr, link: bool, args: str){
  let list = listc(&dir);
  print("compile_dir '{}' -> {} elems\n", dir, list.len());
  for(let i = 0;i < list.len();++i){
    let name_c: CStr* = list.get_ptr(i);
    let name: str = name_c.get(); 
    if(!name.ends_with(".x")) continue;
    let file: String = dir.get_heap();
    file.append("/");
    file.append(name);
    if(is_dir(file.str())) continue;
    cmp.compile(file.cstr());
    if(link){
      cmp.link_run(bin_name(name).str(), args);
    }
  }
}
func compile_dir2(dir: CStr, args: str){
  let list = listc(&dir);
  print("compile_dir '{}' -> {} elems\n", dir, list.len());
  for(let i = 0;i < list.len();++i){
    let name_c: CStr* = list.get_ptr(i);
    let name: str = name_c.get(); 
    if(!name.ends_with(".x")) continue;
    let file: String = dir.get_heap();
    file.append("/");
    file.append(name);
    if(is_dir(file.str())) continue;
    Compiler::compile_single(root().str(), get_out().str(), file.str(), args);
  }
}

func compile(cmp: Compiler*, file: str){
    cmp.compile(file.str().cstr());
    let noext = Path::new(file.str()).noext();
    cmp.link_run(noext,"");
}

func compiler_test(std_test: bool){
  print("compiler_test\n");
  if(std_test){
    build_std();
    compile_dir2(CStr::new("../tests/std_test"), format("{}/std.a", get_out()).str());
  }else{
    compile_dir2(CStr::new("../tests/normal"), "");
  }
}

func bootstrap(){
  print("test::bootstrap\n");
  let root: str = root();
  let ctx: Context = make_context();
  let cmp = Compiler::new(ctx);
  //compile_dir(&cmp, CStr::new("../tests/parser"), false);
  let arr = ["../tests/std/string.x",
            "../tests/std/str.x",
            "../tests/std/ops.x",
            "../tests/std/libc.x",
            "../tests/std/io.x"];
  for(let i = 0;i < arr.len();++i){
    let file = arr[i];
    cmp.compile(CStr::new(file));
    if(i == 0){
      break;//todo
    }
  }
  //cmp.link_run("x", "libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++");
  Drop::drop(cmp);
}

func main(argc: i32, args: i8**){
  print("##########running##########\n");
  print_unit = false;
  if(argc == 1){
    bootstrap();
    return;
  }
  let a1 = get_arg(args, 1);
  if(a1.eq("test")){
    compiler_test(false);
    return;
  }
  else if(a1.eq("test2")){
    compiler_test(true);
    return;
  }else if(a1.eq("std")){
    build_std();
  }
  else if(a1.eq("c")){
    let path = get_arg(args, 2);
    let ctx = make_context();
    let cmp = Compiler::new(ctx);
    if(is_dir(path)){
      compile_dir(&cmp, CStr::new(path), true);
    }else{
      cmp.compile(CStr::new(path));
    }
  }

  
}