class List<T>{
  arr: T*;
  count: int;
  cap: int;

  static func new(): List<T>*{
    return List<T>::new(10);
  }

  static func new(cap: int): List<T>*{
    return new List<T>{arr: malloc<T>(cap), count: 0, cap: cap};
  }

  func expand(){
    if(count < cap){
      return;
    }
    let tmp = malloc<T>(cap * 2);
    let i = 0;
    while(i < count){
      tmp[i] = arr[i];
      ++i;
    }
    arr = tmp;
    cap = cap * 2;
  }

  func add(e: T){
    expand();
    arr[count] = e;
    ++count;
  }

  func add(list: List<T>*){
    let i = 0;
    while(i < list.count){
        add(list.get(i));
        ++i;
    }
  }

  func get(pos: int): T{
    if(pos >= count) {
      panic("index %d out of bounds %d",pos, count);
    }
    return arr[pos];
  }

  func clear(){
    //todo dealloc
    count = 0;
  }

  func size(): int{
    return count;
  }

  func indexOf(e: T): int{
    return indexOf(e, 0);
  }

  func indexOf(e: T, off: int): int{
    let i = off;
    while(i < count){
      if(arr[i] == e) return i;
      ++i;
    }
    return -1;
  }

  func contains(e: T): bool{
    return indexOf(e) != -1;
  }
}

func listTest(){
  let list = List<int>::new(2);
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