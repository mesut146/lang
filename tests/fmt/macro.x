macro noop{
    let x = 1;
}

macro swap(a: Expr,b: Expr){
      let t = a;
    a = b;
          b = t;
}

macro add(a: i32,b: i32){
      a + b
}

macro bump(e: Expr,   by: i32){
    e = e + by;
}

macro each(vals: Expr...){
      $(   print("v={}\n",$vals);   )*
}

macro checked(xs: Expr...){
  if(true){
       $( assert($xs > 0); )*
  }
}

mod   m{
    macro  scaled(e: Expr){
        e = e * 2;
    }
}

use m::{scaled};

func main(){
    let a = 1;
    let b = 2;
    swap!(a,b);
    noop!();
    assert(a == 2);
    assert(add!(a,b) == 3);
    bump!(a,4);
    assert(a == 6);
    m::scaled!(a);
    scaled!(a);
    assert(a == 24);
}
