#include <iostream>
#include "Parser.h"
#include "Lexer.h"

int main()
{
  std::string path("../test");
  Lexer lexer(path);
  Parser parser(lexer);
  parser.parseUnit();
  /*
  for(;;)
  {
    Token t = lexer.next();
    if (t.is(EOF2))
      break;
      printf("type=%d val='%s'\n",t.type,t.value.c_str());
      //std::cout << "type=" << t.type << " val='" << t.value << "'\n";
  }*/
  return 0;
}
