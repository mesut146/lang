import std/it

//A for-each over an *array* used to fail to resolve: the desugar calls
//iter/into_iter on the array type itself, which has no such impl
//("get_impl type not covered: [i32; 3]"). It now iterates a slice *view*
//of the whole array (`arr[0..N]`); a pointer to an array is dereferenced
//first, so the view is of the array itself and not of the (temporary)
//pointer (`(*p)[0..N]`, never `p[0..N]`, which is a slice of a pointer).
//See Resolver::visit_for_each.

func sum_by_value(): i32{
  let a = [1, 2, 3];
  let s = 0;
  for x in a{
    s = s + x;
  }
  //by value copies the elements (no drop type in the way), so the array
  //is still fully usable afterwards
  return s + a[0];
}

func sum_by_ref(): i32{
  let a = [4, 5, 6];
  let s = 0;
  for x in &a{
    s = s + *x;
  }
  return s;
}

func sum_through_ptr_var(): i32{
  let a = [7, 8, 9];
  let p = &a;
  let s = 0;
  for x in p{
    s = s + *x;
  }
  return s;
}

func main(){
  assert(sum_by_value() == 7);
  assert(sum_by_ref() == 15);
  assert(sum_through_ptr_var() == 24);
  print("array foreach done\n");
}
