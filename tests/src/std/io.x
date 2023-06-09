func read_bytes(path: str): List<i8>{
  let f = fopen(path.cstr(), "r".cstr());
  fseek(f, 0, SEEK_END());
  let size = ftell(f);
  //print("size = %lld\n", size);
  fseek(f, 0, SEEK_SET());
  let res = List<i8>::new(size);
  let buf = [0i8; 1024];
  while(true){
      let rcnt = fread(&buf[0], 1, 1024, f);
      if(rcnt <= 0){ break; }
      res.add(buf[0..rcnt]);
  }
  fclose(f);
  return res;
}