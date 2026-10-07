import own/common

//match-value with block (STMT) arms yielding payloads and temps.
enum E{
  V{v: A},
  W
}

func blkbind(o: E): A {
  let x = match o {
    E::V(s) => {
      s
    },
    _ => {
      A::new(98)
    }
  };
  return x;
}

func blktemp(o: E): A {
  let x = match o {
    E::V(s) => {
      A::new(s.a)
    },
    _ => {
      A::new(98)
    }
  };
  return x;
}

func main(){
  //block arm yields the binding.
  reset();
  let a = blkbind(E::V{v: A::new(1)});
  check_ids();
  send(a);
  check_ids(1);

  //block arm yields a temp built from the binding: the binding copy
  //drops in-arm, the scrutinee leaks (bind-time consume), the fresh
  //temp moves to the caller.
  reset();
  let b = blktemp(E::V{v: A::new(2)});
  check_ids(2);
  reset();
  send(b);
  check_ids(2);

  //wildcard block temp.
  reset();
  let c = blkbind(E::W);
  check_ids();
  send(c);
  check_ids(98);

  print("block yield done\n");
}
