#include <iostream>
#include <cstring>
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
  }
}

void parse(std::string &path)
{
  try
  {
    Lexer lexer(path);
    Parser parser(lexer);
    Unit u = parser.parseUnit();
    std::cout << u.print();
  }
  catch (std::string s)
  {
    std::cout << s;
    ;
  }
}

int main(int argc, char **args)
{
  std::string path("../test");
  if (argc > 1 && strcmp(args[1], "lex") == 0)
  {
    lex(path);
  }
  else
  {
    parse(path);
  }
  return 0;
}
