import Option

trait Iterator<T>{
  func next(self): Option<T>;
  func has(self): bool;
}


