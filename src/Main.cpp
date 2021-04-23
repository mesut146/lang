#include <iostream>
#include "Parser.h"
#include "Lexer.h"

void lex(std::string &path)
{
  Lexer lexer(path);

  for (;;)
  {
    Token t = *lexer.next();
    if (t.is(EOF2))
      break;
    printf("type=%d val='%s'\n", t.type, t.value->c_str());
    //std::cout << "type=" << t.type << " val='" << t.value << "'\n";
  }
}

void parse(std::string &path)
{
  try{
  Lexer lexer(path);
  Parser parser(lexer);
  Unit u = parser.parseUnit();
  std::cout << u.print();
  
  }catch(std::string s){
    std::cout << s;;
  }
}

int main()
{
  std::string path("../test");
  //lex(path);
  parse(path);
  return 0;
}
