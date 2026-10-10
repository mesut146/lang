struct A{
  s: String;
  a: i32;
}
func take(s: String){
}

//move out of pointer heals by reassign (see doc/move_ptr_field.txt);
//non-drop derefs and ptr::deref stay free.
func main(){
  let a = A{s: String::new("hi"), a: 1};
  let p = &a;
  take(p.s);
  p.s = String::new("yo");
  print("{}\n", a.a);

  let n = 5;
  let pn = &n;
  let m = *pn;
  assert(m == 5);

  let q = &a;
  assert(ptr::deref!(q).a == 1);

  print("ptr move done\n");
}
