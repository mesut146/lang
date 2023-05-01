class A{
    a: i32;
    b: [i32; 100];
}

func make_arr(): [i32; 100]{
    return [0; 100];
}

func make_A(): A{
    let arr = [0; 100];
    return A{a: 10, b: arr};
}

func ret_mc(): A{
  return make_A();
}

func ret_mc2(): A{
  return A{5, make_arr()};
}

func main(){
    let arr = [0; 100];
    //let obj = A{a: 10, b: arr};
    print("retTest done\n");
}