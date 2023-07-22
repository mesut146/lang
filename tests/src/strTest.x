func main(){
    let helloArr = ['h' as u8, 'e', 'l', 'l', 'o'];
    let helloSlice = helloArr[0..5];
    let s = str::new(helloSlice);

    lit();
    //fix();

    print("strTest done\n");
}

func fix(){
  let s1 = "hello world";
  let s2 = str{s1.buf[6..11]};
  s2.dump();
}

func lit(){
  let s1 = "hello world";
  s1.dump();
  assert s1.len() == 11;
  assert s1.get(1) == 'e';
  //s1.buf[0] = 'H' as i8; //error mutate glob
  assert s1.indexOf("ll", 0) == 2;
  let s2 = s1.substr(6, 11);
  s2.dump();
  assert s2.eq("world");
}