import it
import Option
import ops
import str

class List<T>{
  arr: T*;
  count: i64;
  cap: i64;
}

impl List<T>{
  func new(): List<T>{
    return List<T>::new(10);
  }

  func new(cap: i64): List<T>{
    return List<T>{arr: malloc<T>(cap), count: 0, cap: cap};
  }

  func expand(self){
    if(self.count < self.cap){
      return;
    }
    let tmp = malloc<T>(self.cap * 2);
    for(let i = 0;i < self.count;++i){
      tmp[i] = self.arr[i];
    }
    self.arr = tmp;
    self.cap = self.cap * 2;
  }
  
  func remove(self, pos: i64){
    //copy right of pos to 1 left
    for(let i = pos;i < self.count - 1;++i){
      self.arr[i] = self.arr[i + 1];
    }
    self.count =- 1;
  }

  func add(self1, e: T){
    self1.expand();
    self1.arr[self1.count] = e;
    ++self1.count;
  }

  func add(self, list: List<T>*){
    let i = 0;
    while(i < list.count){
        self.add(list.get(i));
        ++i;
    }
  }

  func add(self, sl: [T]){
    let i = 0;
    while(i < sl.len){
        self.add(sl[i]);
        ++i;
    }
  }

  func set(self, pos: i64, val: T){
      self.arr[pos] = val;
  }

  func get(self, pos: i64): T{
    if(pos >= self.count) {
      panic("index %d out of bounds %d", pos, self.count);
    }
    return self.arr[pos];
  }
  func get_ptr(self, pos: i64): T*{
    if(pos >= self.count) {
      panic("index %d out of bounds %d", pos, self.count);
    }
    return &self.arr[pos];
  }

  func clear(self){
    //todo dealloc
    self.count = 0;
  }

  func size(self): i64{
    return self.count;
  }

  func len(self): i64{
    return self.count;
  }  

  func indexOf(self, e: T): i32{
    return self.indexOf(e, 0);
  }

  func indexOf(self, e: T, off: i32): i32{
    let i = off;
    while(i < self.count){
      if(self.arr[i] == e) return i;
      ++i;
    }
    return -1;
  }
  
  func indexOf2<Q>(self, e: Q, off: i32): i32{
    let i = off;
    while(i < self.count){
      if(Eq::eq(self.arr[i], e)) return i;
      ++i;
    }
    return -1;
  }

  func contains(self, e: T): bool{
    return self.indexOf(e) != -1;
  }

  func slice(self, start: i64, end: i64): [T]{
    return self.arr[start..end];
  }
  
  func iter(self): ListIter<T>{
    return ListIter<T>{list: self, pos: 0};
  }
  func last(self): T*{
    return self.last(0);
  }
  func last(self, off: i64): T*{
    return self.get_ptr(self.count - 1 - off);
  }
  
  func clone(self): List<T>{
    let res = List<T>::new(self.cap);
    res.add(&self);
    return res;
  }
}

impl Debug for List<T>{
  func debug(self, f: Fmt*){
    f.print("[");
    for(let i=0;i<self.count;++i){
      Debug::debug(self.get(i), f);
    }
    f.print("]");
  }
}

class ListIter<T>{
  list: List<T>;
  pos: i32;
}

impl Iterator<T> for ListIter<T>{
  func has(self): bool{
    return self.pos < self.list.len();
  }

  func next(self): Option<T>{
    if(self.has()){
      let p = self.pos;
      self.pos+=1;
      return Option<T>::Some{self.list.get(p)};
    }
    return Option<T>::None;
  }
}

func iterTest(list: List<i32>){
  let it = list.iter();
  assert it.has();
  let n1=it.next();
  assert n1.unwrap() == 10;
  let n2=it.next();
  assert n2.unwrap() == 20;
}

class LA{
  a: i8;
  b: i64;
}

func listStruct(){
  let list = List<LA>::new();
  list.add(LA{5i8, 10});
  list.add(LA{10i8, 20});
  let v1 = list.last(1);
  assert v1.a == 5 && v1.b == 10;
  let v2 = list.last();
  assert v2.a == 10 && v2.b == 20;
}

class LB{
 a: str;
 b: i32;
}

func listStruct2(){
  let list = List<LB>::new();
  list.add(LB{"foo", 10});
  list.add(LB{"bar", 20});
  let v1 = list.get(0);
  let v2 = list.get(1);
  print("v1.b=%d\n", v1.b);
  print("v2.b=%d\n", v2.b);
  assert v1.b == 10;
  assert v2.b == 20;
}

class Align{
  a: i8;
  b: i16;
  c: i64;
}

func al(a: Align*){
  print("algn %d %d %lld\n", a.a, a.b, a.c);
}

func listAlign(){
  let arr = malloc<Align>(10);
  let e1 = Align{1i8, 2i16, 3};
  let e2 = Align{4i8, 5i16, 6};
  let e3 = Align{10i8, 20i16, 30};
  arr[0] = e1;
  let xx = arr[0];
  al(&xx);
  al(&arr[0]);
  //assert false;
}

func listTest(){
  let list = List<i32>::new(2);
  list.add(10);
  list.add(20);
  list.add(30);//trigger expand
  assert list.get(0) == 10;
  assert list.get(1) == 20;
  assert list.get(2) == 30;
  //list.get(3); //will panic
  assert list.indexOf(20) == 1;
  assert list.contains(30) && !list.contains(40);
  let s = list.slice(1, 3);
  assert s.len == 2 && s[0] == 20;
  iterTest(list);
  list.remove(1);
  listStruct();
  //listStruct2();
  listAlign();
  print("listTest done\n");
}