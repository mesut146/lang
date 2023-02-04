func ifTest(){
  let b = true;
  let inIf = false;
  let inElse = false;
  if(b){
    inIf = true;
  }else{
    inElse = true;
  }
  assert inIf;
  assert inElse == false;
  
  print("ifTest done\n");
}

func elseTest(){
  let b = false;
  let inIf = false;
  let inElse = false;
  if(b){
    inIf = true;
  }else{
    inElse = true;
  }
  assert inElse;
  assert inIf == false;
  
  print("elseTest done\n");
}

func whileTest(){
  let i = 0;
  while(i < 10){
    if(i % 2==0) {
      ++i;
      continue; 
    }
    print("i=%d, ", i);
    ++i;
  }
  print("\nwhileTest done\n");
}

func forTest(){
  for(let i = 0, j = 1; i < 10; ++i, ++j){
    if(i % 2 == 0) {
      continue; 
    }
    print("i=%d, ", i);
  }
  print("\nforTest done\n");
}

func flowTest(){
  ifTest();
  elseTest();
  whileTest();
  forTest();
}