func main(){
    bug();
    let helloArr = ['h' as u8, 'e', 'l', 'l', 'o'];
    let helloSlice = helloArr[0..5];
    let s = str::new(helloSlice);

    lit();

    print("strTest done\n");
}

func bug(){
  let arr = ['h' as i8, 'e', 'l'];
  let len = 3;
  let s = String::new(arr[0..len]);
}


func lit(){
  let s1 = "hello world";
  assert s1.len() == 11;
  assert s1.get(1) == 'e';
  assert s1.eq("hello world");
  //s1.buf[0] = 'H' as i8; //error mutate glob
  assert s1.indexOf("ll", 0) == 2;
  let s2 = s1.substr(6, 11);
  assert s2.eq("world");
}