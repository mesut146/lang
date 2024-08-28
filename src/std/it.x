trait Iterator<Item>{
  func next(self): Option<Item>;
}

trait IntoIterator<S>{
  func into_iter(): S;
}

//slice
struct IterSlice<T>{
  slice: [T];
  pos: i32;
}
impl<T> IterSlice<T>{
  func new(slice: [T]): IterSlice<T>{
    return IterSlice{slice, 0};
  }
}
impl<T> Iterator<T*> for IterSlice<T>{
  func next(self): Option<T*>{
    if(self.pos < self.slice.len()){
      let idx = self.pos;
      self.pos += 1;
      return Option::new(&self.slice[idx]);
    }
    return Option<T>::new();
  }
}

struct IntoIterSlice<T>{
  slice: [T];
  pos: i32;
}
impl<T> IntoIterSlice<T>{
  func new(slice: [T]){
    return IterSlice{slice, 0};
  }
}
impl<T> Iterator<T> for IntoIterSlice<T>{
  func next(self): Option<T>{
    if(self.pos < self.slice.len()){
      let idx = self.pos;
      self.pos += 1;
      return Option::new(self.slice[idx]);
    }
    return Option<T>::new();
  }
}

impl<T> [T]{
  func iter(self): IterSlice<T>{
    return IterSlice::new(*self);
  }
  func into_iter(self): IntoIterSlice<T>{
    return IntoIterSlice{*self, 0};
  }
}

struct Range{
  start: i32;
  end: i32;
}
struct RangeIterator{
  pos: i32;
  end: i32;
}

func range(start: i32, end: i32): Range{
  return Range{start: start, end: end};
}

impl Range{
  func iter(self): RangeIterator{
    return RangeIterator{pos: self.start, end: self.end};
  }
  func into_iter(self): RangeIterator{
    return RangeIterator{pos: self.start, end: self.end};
  }
}

impl Drop for RangeIterator{
  func drop(*self){}
}

impl Iterator<i32> for RangeIterator{
  func next(self): Option<i32>{
    if(self.pos < self.end){
      let idx = self.pos;
      self.pos += 1;
      return Option::new(idx);
    }
    return Option<i32>::new();
  }
}

func range_test(){
  for i in range(1, 10){
    print("i={}", i);
  }
}