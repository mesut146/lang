class str{
  buf: [i8];
}

impl str{
    func len(self): i32{
      return self.buf.len;
    }
    func new(buf: [i8]): str{
        return str{buf: buf};
    }
}


func strTest(){
    let helloArr = [104i8, 101i8, 108i8, 108i8, 111i8];
    let helloSlice = helloArr[0..1];
    let s = str::new(helloSlice);
}