import std/it
import std/ops
import std/libc

#drop
struct List<T>{
  ptr: T*;
  count: i64;
  cap: i64;
}

impl<T> List<T>{
  func new(): List<T>{
    return List<T>::new(10);
  }

  func get_malloc(size: i64): T*{
    if(size < 0){
      panic("invalid size {}", size);
    }
    let ptr = malloc<T>(size);
    if(ptr as u64 == 0){
      printf("size=%lld\n", size);
      panic("malloc returned null");
    }
    return ptr;
  }

  func new(cap: i64): List<T>{
    let ptr = List<T>::get_malloc(cap);
    return List<T>{ptr: ptr, count: 0, cap: cap};
  }

  func ptr(self): T*{
    return self.ptr;
  }

  func capacity(self): i64{
    return self.cap;
  }

  func clear(self){
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

  func expand(self){
    if(self.count < self.cap){
      return;
    }
    let tmp = List<T>::get_malloc(self.cap + 10);
    for(let i = 0;i < self.count;++i){
      let old: T = ptr::deref!(self.get(i));
      ptr::copy!(tmp, i, old);
      std::no_drop(old);
    }
    free(self.ptr as i8*);
    self.ptr = tmp;
    self.cap = self.cap + 10;
  }

  func in_index(self, pos: i64): bool{
    return pos >= 0 && pos < self.count;
  }
  
  func check(self, pos: i64){
    if(pos >= 0 && pos < self.count){
      return;
    }
    //panic("index {} out of bounds ({}, {})", pos, 0, self.count);
    printf("index %d out of bounds (%d, %d)\n", pos, 0, self.count);
    exit(1);
  }
  
  func remove(self, pos: i64): T{
    self.check(pos);
    let elem = self.get_internal(pos);
    //shift rhs of pos to 1 left
    for(let i = pos;i < self.count - 1;++i){
      let lhs: T* = ptr::get!(self.ptr, i);
      std::no_drop(*lhs);
      *lhs = ptr::deref!(ptr::get!(self.ptr, i + 1));
    }
    self.count -= 1;
    return elem;
  }

  func pop_back(self): T{
    let idx = self.len() - 1;
    return self.remove(idx);
  }

  func add(self, e: T): T*{
    self.expand();
    ptr::copy!(self.ptr, self.count, e);
    std::no_drop(e);//add this to prevent dropping e
    ++self.count;
    return self.get(self.count - 1);
  }

  func add(self, val: T, pos: i32){
    //add val to desired position
    self.expand();
    if(pos < 0 || pos >= self.len()){
      panic("index {} out of bounds ({}, {})", pos, 0, self.len());
    }

    //shift rhs of pos to 1 right
    //pos will be empty after this
    for(let i = self.count - 1;i >= pos;i = i - 1){
      let lhs: T* = ptr::get!(self.ptr, i);
      let rhs: T* = ptr::get!(self.ptr, i + 1);
      std::no_drop(*rhs);
      *rhs = ptr::deref!(lhs);
    }
    //place value to cleared spot
    ptr::copy!(self.ptr, pos, val);
    std::no_drop(val);
    self.count += 1;
  }

  func add_not_exist(self, e: T){
    if(self.contains(&e)){
      e.drop();
      return;
    }
    self.add(e);
  }

  func add_list(self, list: List<T>){
    let i = 0;
    while(i < list.count){
        self.add(list.get_internal(i));
        ++i;
    }
    //elems alive, just free main mem
    free(list.ptr as i8*);
    std::no_drop(list);
  }

  func add_slice(self, sl: [T]){
    let i = 0;
    while(i < sl.len()){
        self.add(sl[i]);
        ++i;
    }
  }

  func set(self, pos: i64, val: T): T{
      let old = self.get_internal(pos);
      ptr::copy!(self.ptr, pos, val);
      std::no_drop(val);
      return old;
  }

  func get_internal(self, pos: i64): T{
    return ptr::deref!(self.get(pos));
  }

  func get(self, pos: i64): T*{
    self.check(pos);
    return ptr::get!(self.ptr, pos);
  }


  func indexOf(self, e: T*): i32{
    return self.indexOf(e, 0);
  }
  
  func indexOf(self, e: T*, off: i32): i32{
    let i = off;
    while(i < self.count){
      if(Eq::eq(self.get(i), e)) return i;
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

  func into_iter(*self): ListIntoIter<T>{
    return ListIntoIter<T>{list: self, pos: 0};
  }

  func last(self): T*{
    return self.last(0);
  }
  func last(self, off: i64): T*{
    return self.get(self.count - 1 - off);
  }

  func swap(self, i: i32, j: i32){
    let cur = self.get_internal(i);
    let next = self.set(j, cur);
    let cur2 = self.set(i, next);
    std::no_drop(cur2);
  }

  func sort(self){
    //bubble sort for now
    for(let i = 0;i < self.len();++i){
      for(let j = 0;j < self.len() - i - 1;++j){
        let a1 = self.get(j);
        let a2 = self.get(j + 1);
        let cmp = Compare::compare(a1, a2);
        //a1 > a2
        if(cmp > 0){
          self.swap(j, j + 1);
        }
      }
    }
  }
  
  func find(self, f: func(T*)=> bool): i32{
      for(let i = 0;i < self.len();++i){
          let e = self.get(i);
          if(f(e)){
              return i;
          }
      }
      return -1;
  }
  
  func filter(self, f: func(T*)=> bool): List<T*>{
      let res = List<T*>::new();
      for(let i = 0;i < self.len();++i){
          let e = self.get(i);
          if(f(e)){
              res.add(e);
          }
      }
      return res;
  }
  
  func map<E>(self, f: func(T*)=> E): List<E>{
      let res = List<E>::new();
      for(let i = 0;i < self.len();++i){
          let e = self.get(i);
          res.add(f(e));
      }
      return res;
  }
}

impl<T> Debug for List<T>{
  func debug(self, f: Fmt*){
    f.print("[");
    for(let i = 0;i < self.count;++i){
      if(i > 0) f.print(", ");
      Debug::debug(self.get(i), f);
    }
    f.print("]");
  }
}

impl<T> Clone for List<T>{
  func clone(self): List<T>{
    let res = List<T>::new(self.count);
    for(let i = 0;i < self.len();++i){
      let elem = self.get(i);
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

impl<T> Eq for List<T>{
    func eq(self, list: List<T>*): bool{
        if(self.len() != list.len()) return false;
        for(let i = 0;i < self.len();i += 1){
            let e1 = self.get(i);
            let e2 = list.get(i);
            if(!Eq::eq(e1, e2)){
                return false;
            }
        }
        return true;
    }
}

//iters
struct ListIter<T>{
  list: List<T>*;
  pos: i32;
}
impl<T> Iterator<T*> for ListIter<T>{
  func next(self): Option<T*>{
    if(self.pos < self.list.len()){
      let idx = self.pos;
      self.pos += 1;
      return Option::new(self.list.get(idx));
    }
    return Option<T*>::new();
  }
}

struct ListIntoIter<T>{
  list: List<T>;
  pos: i32;
}
impl<T> Iterator<T> for ListIntoIter<T>{
  func next(self): Option<T>{
    if(self.pos < self.list.len()){
      let idx = self.pos;
      self.pos += 1;
      return Option::new(ptr::deref!(self.list.get(idx)));
    }
    return Option<T>::new();
  }
}
impl<T> Drop for ListIntoIter<T>{
  func drop(*self){
    //elems alive, drop main memory only
    free(self.list.ptr as i8*);
  }
}