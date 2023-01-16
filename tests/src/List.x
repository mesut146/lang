class List<T>{
  arr: T*;
  count: int;
  cap: int;

  static func new(): List<T>*{
    return new List<T>{arr: malloc<T>(10), count: 0, cap: 10};
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

  /*func add(list: List<T>){
    let i = 0;
    while(i < list.count){
        add(list.get(i));
        ++i;
    }
  }*/

  func get(pos: int): T{
    //if(pos >= count) panic("index out of bounds");
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
    let i = 0;
    while(i < count){
      if(arr[i] == e) return i;
      ++i;
    }
    return -1;
  }
}

func listTest(){
  let list1 = List<int>::new();
  let list = new List<int>{arr: malloc<int>(2), count: 0, cap: 2};
  list.add(1);
  list.add(2);
  list.add(3);//trigger expand
  assert list.get(0) == 1;
  assert list.get(1) == 2;
  assert list.get(2) == 3;
  print("listTest done\n");
}