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
  func new(slice: [T]){
    return IterSlice{slice, pos: 0};
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
    return IterSlice{slice, pos: 0};
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
}