#include <iostream>
#include "Lexer.h"

int main()
{
  std::string path("../test");
  Lexer l(path);
  for(;;)
  {
    Token t = l.next();
    if (t.is(EOF2))
      break;
    std::cout << "type=" << t.type << " val=" << t.value << "\n";
  }
  return 0;
}
