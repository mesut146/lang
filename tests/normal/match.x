struct A{
    a: i64;
    b: i64;
}

enum E{
    E1,
    E2(val: i32, a: A),
    E3(val: i32)
}

func blk(){
  let x = {
    let a = 5;
    a
  };
  assert(x == 5);
}

func get(val: i32): i32{
    return val;
}

func blk_if(c: bool, val1: i32, val2: i32): i32{
    let x = if(c){
        val1
    }else{
        get(val2)
    };
    return x;
}

/*func blk2(c: bool, c2: bool, x: i64, y: i64): A{
    if(c){
        if(c2){
            A{a: x, b: y}
        }else{
            A{a: x, b: y}
        }
    }else{
        A{a: x, b: y}
    }
}*/

func main(){
    blk();
    assert(blk_if(true, 10, 20) == 10);
    assert(blk_if(false, 10, 20) == 20);
    let e = E::E1;
    /*match &e {
        E1 => print("E1\n"),
    }*/
    print("match done\n");
}