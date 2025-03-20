import std/libc
import std/any

type FUNC_TYPE = func(c_void*) => void;

struct Process{
    fp: FILE*;
}
impl Process{
    func run(cmd: str): Process{
        let cs = cmd.cstr();
        let mode = "r".cstr();
        let fp = popen(cs.ptr(), mode.ptr());
        if(is_null(fp)){
            panic("failed to run {}", cmd);
        }
        cs.drop();
        mode.drop();
        return Process{fp: fp};
    }
    func read_str(self): String{
        return String::new(self.read());
    }
    func read(self): List<u8>{
        let res = List<u8>::new();
        let buf = [0u8; 1024];
        while(true){
            let cnt = fread(&buf[0], 1, 1024, self.fp);
            if(cnt <= 0){ break; }
            res.add_slice(buf[0..cnt]);
        }
        return res;
    }
    func close(*self){
        pclose(self.fp);
    }
    func eat_close(*self){
        self.read().drop();
        self.close();
    }
}

impl Drop for Process{
    func drop(*self){
        self.eat_close();
    }
}

static root_exe = Option<String>::new();
struct CmdArgs{
  args: List<String>;
  root: String;
}

impl CmdArgs{
  func get_arg(args: i8**, idx: i32): str{
    let ptr = *ptr::get(args, idx) as u8*;
    if(ptr as u64 == 0){
      panic("ptr is null");
    }
    let len = strlen(ptr as i8*);
    return str::new(ptr[0..len]);
  }
  func new(argc: i32, args: i8**): CmdArgs{
    let root = CmdArgs::get_arg(args, 0).str();
    print("root={}\n", root);
    root_exe.set(root.clone());
    let res = CmdArgs{args: List<String>::new(), root: root};
    for(let i = 1; i < argc;++i){
      res.args.add(CmdArgs::get_arg(args, i).str());
    }
    return res;
  }
  func get_root(self): str{
    return self.root.str();
  }
  func consume(self){
    let arg = self.get();
    arg.drop();
  }
  func peek(self): String*{
    return self.args.get(0);
  }
  func get(self): String{
    if(self.args.len() == 0){
      panic("no more arguments");
    }
    let res = self.args.remove(0);
    return res;
  }
  func has(self): bool{
    return self.args.len() > 0;
  }
  func is(self, arg: str): bool{
    return self.args.get(0).eq(arg);
  }
  func end(self){
      if(self.args.empty()) return;
      panic("extra args: {:?}", self.args);
  }

  func has_any(self, arg: str): bool{
    for arg1 in &self.args{
      if(arg1.eq(arg)){
        return true;
      }
    }
    return false;
  }
  func consume_any(self, arg: str): bool{
    for(let i = 0; i < self.args.len(); ++i){
      if(self.args.get(i).eq(arg)){
        let tmp = self.args.remove(i);
        tmp.drop();
        return true;
      }
    }
    return false;
  }
  func get_val(self, arg: str): Option<String>{
    for(let i = 0; i < self.args.len(); ++i){
      if(self.args.get(i).eq(arg)){
        let val = self.args.remove(i + 1);
        let key = self.args.remove(i);
        key.drop();
        return Option::new(val);
      }
    }
    return Option<String>::new();
  }
  func get_val_or(self, arg: str, def: String): String{
    let val = self.get_val(arg);
    return val.unwrap_or(def);
  }
  func get_val2(self, arg: str): String{
    let val = self.get_val(arg);
    if(val.is_none()){
      panic("expected arg and val: {}", arg);
    }
    return val.unwrap();
  }
}