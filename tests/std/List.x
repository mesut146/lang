import std/it
import std/ops
import std/libc

#drop
struct List<T>{
  ptr: T*;
  count: i64;
  cap: i64;
}

func get_malloc<T>(size: i64): T*{
  let ptr = malloc<T>(size);
  if(ptr as u64 == 0){
    panic("malloc returned null for size: {}", size);
  }
  return ptr;
}

impl<T> List<T>{
  func new(): List<T>{
    return List<T>::new(10);
  }

  func new(cap: i64): List<T>{
    let ptr = get_malloc<T>(cap);
    return List<T>{ptr: ptr, count: 0, cap: cap};
  }

  func ptr(self): T*{
    return self.ptr;
  }

  func expand(self){
    if(self.count < self.cap){
      return;
    }
    let tmp = get_malloc<T>(self.cap + 10);
    for(let i = 0;i < self.count;++i){
      //*ptr::get(tmp, i) = *ptr::get(self.ptr, i);
      let old = ptr::deref(ptr::get(self.ptr, i));
      ptr::copy(tmp, i, old);
      std::no_drop(old);
    }
    free(self.ptr as i8*);
    self.ptr = tmp;
    self.cap = self.cap + 10;
  }
  
  func check(self, pos: i64){
    if(pos >= 0 && pos < self.count){
      return;
    }
    panic("index out of bounds {}", pos);
  }
  
  func remove(self, pos: i64){
    self.check(pos);
    let elem = self.get_internal(pos);
    Drop::drop(elem);
    //shift rhs of pos to 1 left
    for(let i = pos;i < self.count - 1;++i){
      let lhs = ptr::get(self.ptr, i);
      *lhs = ptr::deref(ptr::get(self.ptr, i + 1));
    }
    self.count -= 1;
  }

  func pop_back(self){
    let idx = self.len() - 1;
    self.remove(idx);
  }

  func add(self, e: T){
    self.expand();
    let trg = ptr::get(self.ptr, self.count);
    //*ptr::get(self.ptr, self.count) = e;
    ptr::copy(self.ptr, self.count, e);
    //memcpy(trg as i8*, &e as i8*, std::size<T>());
    std::no_drop(e);//add this to prevent dropping e
    ++self.count;
  }

  func add(self, list: List<T>){
    let i = 0;
    while(i < list.count){
        self.add(list.get_internal(i));
        ++i;
    }
    //elems alive, just free main mem
    free(list.ptr as i8*);
    std::no_drop(list);
  }

  func add(self, sl: [T]){
    let i = 0;
    while(i < sl.len()){
        self.add(sl[i]);
        ++i;
    }
  }

  func set(self, pos: i64, val: T){
      //*self.get_ptr_write(pos) = val;
      ptr::copy(self.ptr, pos, val);
  }

  func get_internal(self, pos: i64): T{
    return ptr::deref(self.get_ptr(pos));
  }
  
  func get_ptr(self, pos: i64): T*{
    if(pos >= self.count) {
      panic("index {} out of bounds {}", pos, self.count);
    }
    return ptr::get(self.ptr, pos);
  }

  func get(self, pos: i64): T{
    if(!std::is_ptr<T>()){
      panic("can't get non ptr");
    }
    return *(self.get_ptr(pos));
  }

  /*func get_ptr_write(self, pos: i64): T*{
    if(pos >= self.cap) {
      panic("index {} out of bounds {}", pos, self.count);
    }
    return ptr::get(self.ptr, pos);
  }*/

  func clear(self){
    //todo dealloc
    self.drop_elems();
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

  func indexOf(self, e: T*): i32{
    return self.indexOf(e, 0);
  }
  
  func indexOf(self, e: T*, off: i32): i32{
    let i = off;
    while(i < self.count){
      if(Eq::eq(self.get_ptr(i), e)) return i;
      ++i;
    }
    return -1;
  }

  func contains(self, e: T*): bool{
    return self.indexOf(e) != -1;
  }

  func slice(self, start: i64, end: i64): [T]{
    return self.ptr[start..end];
  }

  func slice(self): [T]{
    return self.slice(0, self.len());
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
  
}

impl<T> Debug for List<T>{
  func debug(self, f: Fmt*){
    f.print("[");
    for(let i = 0;i < self.count;++i){
      if(i > 0) f.print(", ");
      Debug::debug(self.get_ptr(i), f);
    }
    f.print("]");
  }
}

// struct ListIter<T>{
//   list: List<T>*;
//   pos: i32;
// }

// impl<T> Iterator<T> for ListIter<T>{
//   func has(self): bool{
//     return self.pos < self.list.len();
//   }

//   func next(self): Option<T>{
//     if(self.has()){
//       let p = self.pos;
//       self.pos+=1;
//       return Option<T>::Some{self.list.get(p)};
//     }
//     return Option<T>::None;
//   }
// }

impl<T> Clone for List<T>{
  func clone(self): List<T>{
    let res = List<T>::new(self.count);
    //res.add(self);
    for(let i = 0;i < self.len();++i){
      let elem = self.get_ptr(i);
      res.add(Clone::clone(elem));
    }
    return res;
  }
}

impl<T> Drop for List<T>{
  func drop(*self){
    self.drop_elems();
    free(self.ptr as i8*);
  }

  func drop_elems(self){
    for(let i = 0;i < self.len();++i){
      let ep = self.get_internal(i);
      Drop::drop(ep);
    }
  }
}