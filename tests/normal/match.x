struct A{
    a: i64;
    b: i64;
}

enum E{
    E1,
    E2(val: i32, a: A),
    E3(val: i32)
}

/*func blk(): i32{
  5
}*/

func main(){
    let e = E::E1;
    /*match &e {
        E1 => print("E1\n"),
    }*/
    print("match done\n");
}