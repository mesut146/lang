import std/it
import std/ops

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
  
  func empty(self): bool{
    return self.count == 0;
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
    res.add(self);
    return res;
  }
}

impl Debug for List<T>{
  func debug(self, f: Fmt*){
    f.print("[");
    for(let i=0;i<self.count;++i){
      if(i>0) f.print(", ");
      Debug::debug(self.get(i), f);
    }
    f.print("]");
  }
}

class ListIter<T>{
  list: List<T>*;
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

