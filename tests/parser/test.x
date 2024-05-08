import parser/lexer
import parser/token
import parser/parser
import parser/ast
import parser/printer
import parser/resolver
import parser/compiler
import parser/debug_helper
import parser/bridge
import std/map
import std/io
import std/libc

func root(): str{
  return "../tests";
}

func compile_dir(cmp: Compiler*, dir: CStr, link: bool){
  let list = listc(&dir);
  print("compile_dir '{}' -> {} elems\n", dir, list.len());
  for(let i = 0;i < list.len();++i){
    let name_c: CStr* = list.get_ptr(i);
    let name = name_c.get(); 
    if(!name.ends_with(".x")) continue;
    let file = dir.get_heap();
    file.append("/");
    file.append(name);
    if(is_dir(file.str())) continue;
    cmp.compile(file.cstr());
    if(link){
      cmp.link_run(name.substr(0, name.len() as i32 - 2),"");
    }
  }
}

func compile(cmp: Compiler*, file: str){
    cmp.compile(file.str().cstr());
    let noext = Path::new(file.str()).noext();
    cmp.link_run(noext,"");
}

func compiler_test(){
  print("compiler_test\n");
  let root = root();
  let ctx = Context::new(root.str());
  let cmp = Compiler::new(ctx);
  compile_dir(&cmp, CStr::new("../tests/normal"), true);
  //compile_dir(&cmp, "../tests/src/std", false);
}

func bootstrap(){
  print("test::bootstrap\n");
  let root: str = root();
  let ctx = Context::new(root.str());
  let cmp = Compiler::new(ctx);
  //compile_dir(&cmp, CStr::new("../tests/parser"), false);
  let arr = ["../tests/std/String.x",
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
  if(argc == 1){
    bootstrap();
    return;
  }
  let a1 = get_arg(args, 1);
  if(a1.eq("test")){
    compiler_test();
  }
  else if(a1.eq("c")){
    let path = get_arg(args, 2);
    if(is_dir(path)){
      let root = "../tests/src";
      let ctx = Context::new(root.str());
      let cmp = Compiler::new(ctx);
      compile_dir(&cmp, CStr::new(path), true);
    }else{
      let root = "../tests/src";
      let ctx = Context::new(root.str());
      let cmp = Compiler::new(ctx);
      cmp.compile(CStr::new(path));
    }
  }

  
}