import std/any

//Any auto-drop is type-erased: the boxed payload's own heap is freed only by
//the drop glue handed to Any::new<T>(val, glue). With the glue-less
//Any::new<T>(val) the String buffer leaks. Raw malloc, invisible to the
//drop-count tracker (see bin/test.sh leak); the glue-less form does not even
//compile this file, so the gate fails pre-fix.
struct Payload{
  s: String;
}

func free_payload(p: i8*){
  let v: Payload = ptr::deref!(p as Payload*);
  Drop::drop(v);
}

func main(){
  let a = Any::new(Payload{s: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".owned()}, free_payload);
  print("any_payload done\n");
}
