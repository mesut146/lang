enum E{
    A(a: i32),
    B(a: i64)
}

func get(e: E*): i32*{
    if let E::A(a)= (e){
        return &a;
    }
    panic("");
}

func main(){
  let e = E::A{a: 100};
  get(&e);
}