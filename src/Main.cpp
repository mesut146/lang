#include "Lexer.h"
#include "Parser.h"
#include <cstring>
#include <iostream>

void lex(std::string &path) {
    Lexer lexer(path);

    for (;;) {
        Token t = *lexer.next();
        if (t.is(EOF_))
            break;
        printf("type=%d val='%s'\n", t.type, t.value->c_str());
    }
}

void parse(std::string &path) {
    try {
        Lexer lexer(path);
        Parser parser(lexer);
        Unit u = parser.parseUnit();
        std::cout << u.print() << "\n";
    } catch (std::string s) {
        std::cout << "err:" << s << "\n";
        //print_stacktrace();
    }
}

int main(int argc, char **args) {
    //std::string path("../tests/types");
    std::string path("../tests/stmts");
    //std::string path("../tests/exprs");
    if (argc > 1 && strcmp(args[1], "lex") == 0) {
        lex(path);
    } else {
        parse(path);
    }
    return 0;
}
