struct A{
    a: i32;
}
  
enum En{
    A,
    B(a: A*)
}

func main(){
    let a = get_load();
    assert_eq(a.a, 10);
  
    let a2 = get_load2();
    assert_eq(a2.a, 20);

    print("load_test done\n");
}


func get_load(): A{
    let a = A{a: 5};
    let aptr = &a;
    *aptr = A{a: 10};
    return *aptr;
}
  
func get_load2(): A{
    let a = A{a: 15};
    let aptr = &a;
    *aptr = A{a: 20};

    let b = En::B{aptr};
    if let En::B(a_ptr) = (b){
      return *a_ptr;
    }
    panic("impossible");
}