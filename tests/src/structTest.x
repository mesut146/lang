struct A{
    a: i32;
    b: i32;
}

class B{
    a: A;
    b: i32;
}


func main(){
    //random order
    let obj = A{b: 6, a: 5};
    assert obj.a == 5 && obj.b == 6;
    obj.a = 10;
    assert obj.a == 10 && obj.b == 6;
  
    let b = B{a: obj, b: 3};
    assert b.b == 3;
    assert b.a.a == 10 && b.a.b == 6;
  
    print("structTest done\n");
  }

  