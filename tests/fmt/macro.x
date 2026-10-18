macro noop{
    let x = 1;
}

macro swap(a: Expr,b: Expr){
      let t = a;
    a = b;
          b = t;
}

func main(){
    let a = 1;
    let b = 2;
    swap!(a,b);
    noop!();
    assert(a == 2);
}
