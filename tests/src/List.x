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
    let i = 0;
    while(i < self.count){
      tmp[i] = self.arr[i];
      ++i;
    }
    self.arr = tmp;
    self.cap = self.cap * 2;
  }

  func add(self, e: T){
    self.expand();
    self.arr[self.count] = e;
    ++self.count;
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

  func get(self, pos: i32): T{
    if(pos >= self.count) {
      panic("index %d out of bounds %d", pos, self.count);
    }
    return self.arr[pos];
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

  func contains(self, e: T): bool{
    return self.indexOf(e) != -1;
  }

  func slice(self, start: i64, end: i64): [T]{
    return self.arr[start..end];
  }
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
  print("listTest done\n");
}