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
    if(i % 2 == 0) {
      ++i;
      continue; 
    }
    ++i;
  }
  assert i == 10;
  print("whileTest done\n");
}

func forTest(){
  for(let i = 0, j = 1; i < 10; ++i, ++j){
    if(i % 2 == 0) {
      continue; 
    }
    assert i %2 == 1;
  }
  print("forTest done\n");
}

func prims(){
  let cnt = 0;
  for(let i = 3 ; i < 90 ; i = i + 2){
    let pr = true;
    for (let j = 3; j * j < i; j = j + 2){
      if(i % j == 0){
        pr = false;
        break;
      }
    }
    if(pr){
      ++cnt;
    }
  }
  assert cnt == 26;
  print("prims done\n");
}

func main(){
  ifTest();
  elseTest();
  whileTest();
  forTest();
  prims();
}