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
    //no allocation until something is added: an empty String/List is very
    //common (every temporary and every `String::new()`), and eagerly
    //allocating 10 elements made malloc/free ~11% of a compile. `expand`
    //handles cap 0 (it grows to 10) and free(null) is a no-op.
    return List<T>{ptr: ptr::null<T>(), count: 0, cap: 0};
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
    if(cap <= 0){
      return List<T>{ptr: ptr::null<T>(), count: 0, cap: 0};
    }
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
    //Geometric growth. Growing by 10 copied the whole buffer every tenth add,
    //which is quadratic: the lexer's token list alone was ~15% of a large
    //file's compile time (and it copies every Token's String with it).
    //`reserve` (below) still allocates exactly what a bulk caller asks for.
    let new_cap = self.cap * 2;
    if(new_cap < 10){
      new_cap = 10;
    }
    let tmp = List<T>::get_malloc(new_cap);
    for(let i = 0;i < self.count;++i){
      let old: T = ptr::deref!(ptr::get!(self.ptr, i));
      ptr::copy!(tmp, i, old);
      std::no_drop(old);
    }
    free(self.ptr as i8*);
    self.ptr = tmp;
    self.cap = new_cap;
  }

  //ensure room for `extra` more elems (expand() only guarantees one).
  func reserve(self, extra: i64){
    let need = self.count + extra;
    if(need <= self.cap){
      return;
    }
    //geometric growth, like expand(): `need + 10` reallocated (and recopied
    //the whole buffer) every ~10 bytes when a String grew by repeated appends
    let cap = self.cap * 2;
    if(cap < need + 10){
      cap = need + 10;
    }
    let tmp = List<T>::get_malloc(cap);
    for(let i = 0;i < self.count;++i){
      let old: T = ptr::deref!(ptr::get!(self.ptr, i));
      ptr::copy!(tmp, i, old);
      std::no_drop(old);
    }
    free(self.ptr as i8*);
    self.ptr = tmp;
    self.cap = cap;
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
    //`self.get(self.count - 1)` re-checked bounds through two calls
    return ptr::get!(self.ptr, self.count - 1);
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
    //the check is inlined: a call to check() per index showed up as ~4% of a
    //compile, and every byte loop in String/str goes through here
    if(pos < 0 || pos >= self.count){
      printf("index %d out of bounds (%d, %d)\n", pos, 0, self.count);
      exit(1);
    }
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
    //one call per element (the element's drop glue) instead of len+get_internal
    let p = self.ptr;
    for(let i = 0;i < self.count;++i){
      Drop::drop(ptr::deref!(ptr::get!(p, i)));
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