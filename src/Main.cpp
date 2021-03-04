#include <iostream>
#include "Lexer.h"


int main(){
  std::string path("../test");
  Lexer l(path);
  for(int i=0;i<1000;i++){
  	Token t = l.next();
      if(t.is(EOF2)) break;
      std::cout<<"type="<<t.type<<" val="<<t.value<<"\n";
  }
  return 0;
}
