class Entry<K, V>{
  key: K;
  value: V;
};

class HashMap<K, V>{
  arr: List<Entry<K, V>>;
  size: u32;
}

impl HashMap<K, V>{
  func put(k: K, v: V){
    let i = Hash::hash(k) % self.size;
    let bucket = arr.get(i);
  }

  func get(k: K*): V{

  }
}