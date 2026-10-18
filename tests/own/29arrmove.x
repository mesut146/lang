import own/common

//Moving out of a *constant* index into a local array (`send(a[0])`) used to be
//refused outright. The element is a tracked place now (Rhs::INDEX), exactly
//like a struct field: moving one out suppresses the array's own element-wise
//drop, and the same all-elements rule applies (check_partial), so the whole
//array must be moved out. Reassigning an element that was moved revives it and
//the rest of the array drops as usual (see zpartial.x for the field case).
//
//Still refused, because there is no place state to stop the aggregate from
//dropping a value that already left: a dynamic index, a slice, a pointer
//base, a nested array, and a field of an element (`send(p[0].a)`, which used
//to compile and drop that field twice -- see the fail tests).

#drop
struct P{
  a: A;
  b: A;
}

func take(p: P){
  p.drop();
}

func move_all(){
  let a = [A::new(1), A::new(2)];
  send(a[0]);
  send(a[1]);
  //a is fully consumed: nothing drops here
}

func move_then_reassign(){
  let a = [A::new(10), A::new(11)];
  send(a[0]);            //10
  a[0] = A::new(30);     //element 0 is dead: no drop
  //a drops here: 30 then 11
}

func move_through_struct_array(){
  let p = [P{a: A::new(20), b: A::new(21)}];
  take(p[0]);
  //p[0] moved out whole: nothing drops here
}

func main(){
  move_all();
  check_ids(1, 2);
  reset();

  move_then_reassign();
  check_ids(10, 30, 11);
  reset();

  move_through_struct_array();
  check_ids(20, 21);
  reset();

  print("arrmove done\n");
}
