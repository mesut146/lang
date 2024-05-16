trait Iterator<T>{
  func next(self): Option<T>;
  func has(self): bool;
}

trait IntoIter<S>{
  func iter(): S;
}


impl<T> IntoIter<Holder> for List<T>{
  func iter(self): Holder{
    return Holder{self, 0};
  }
}

