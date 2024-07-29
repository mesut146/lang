//static call_stack = List<str>::new();
static call_stack = [""; 100];
static call_stack_len = 0;

func enter_frame(name: str){
  call_stack[call_stack_len] = name;
  call_stack_len += 1;
}

func exit_frame(){
  //call_stack.remove(call_stack.len() - 1);
  call_stack_len -= 1;
  call_stack[call_stack_len] = "";
}

func print_frame(){
    for(let i = 0;i < call_stack_len;++i){
      let name = call_stack[i];
      printf("%d %s\n", i, name.buf.ptr());
      //print("{} {}\n", i, name);
    }
}