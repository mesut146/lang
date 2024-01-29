static call_stack: List<String> = List<String>::new();

func panic_(msg: str){
    print("panic %s in", msg.cstr());
    for(let i = 0;i < call_stack.size();++i){
      let name = call_stack.get_ptr(i);
      print("%s\n", name.cstr());
    }
  }