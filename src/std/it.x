trait Iterator<Item>{
  func next(self): Option<Item>;
}

trait IntoIter<S>{
  func iter(): S;
}


impl<T> IntoIter<Holder> for List<T>{
  func iter(self): Holder{
    return Holder{self, 0};
  }
}

