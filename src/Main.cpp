#include "parser/Parser.h"
#include "parser/Util.h"
#include "Resolver.h"
#include <cstring>
#include <iostream>

void lex(std::string &path) {
    Lexer lexer(path);

    for (;;) {
        Token t = *lexer.next();
        if (t.is(EOF_))
            break;
        printf("type=%d off=%d val='%s'\n", t.type, t.start, t.value->c_str());
    }
}

void parse(std::string &path) {
        Lexer lexer(path);
        Parser parser(lexer);
        Unit* u = parser.parseUnit();
        std::cout << u->print() << "\n";
}

void resolveTest(){
  //std::string path="../tests/resolve1";
  //std::string path="../tests/resolveClass";
  std::string path="../tests/arrow";
  //std::string path="../tests/core/List";
  Lexer lexer(path);
  Parser parser(lexer);
  Unit* u = parser.parseUnit();
  Resolver r(u);
  r.resolveAll();
}  

int main(int argc, char **args) {
  try{
    if (argc > 1) {
      if(strcmp(args[1], "parse") == 0){
        debug = true;
        auto path = std::string(args[2]);
        parse(path);
      }
      else{
            resolveTest();
       }
    } else {
        debug = true;
        std::string path;
        path = "../tests/types";
        //path = "../doc/join";
        //std::string path("../tests/stmts");
        //std::string path("../tests/exprs");
        //lex(path);
        parse(path);
    }
    } catch (std::string s) {
        std::cout << "err:" << s << "\n";
        //print_stacktrace();
    }catch(...){
       print_stacktrace();
     }
    return 0;
}
