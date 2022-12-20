#include "Resolver.h"
#include "parser/Parser.h"
#include "parser/Util.h"
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

void parse(const std::string &path, bool print = false) {
    info("parsing " + path);
    Lexer lexer(path);
    Parser parser(lexer);
    Unit *u = parser.parseUnit();
    if (print) {
        std::cout << u->print() << "\n";
    }
}

std::string Resolver::root;

void resolveTest() {
    debug = false;
    //std::string path="../tests/resolve1";
    //std::string path="../tests/resolveClass";
    //std::string path="../tests/arrow";
    std::string path = "../tests/importTest";
    //std::string path="../tests/a";
    //std::string path="../tests/core/List";
    Resolver::root = "../tests";
    Resolver *r = Resolver::getResolver(path);
    r->resolveAll();
}

int main(int argc, char **args) {
    try {
        if (argc > 1) {
            if (strcmp(args[1], "parse") == 0) {
                debug = true;
                auto path = std::string(args[2]);
                parse(path);
            } else {
                resolveTest();
            }
        } else {
            debug = true;
            parse("../tests/exprs");
            parse("../tests/Optional");
            parse("../tests/stmts");
            parse("../tests/types");
        }
    } catch (std::exception &e) {
        std::cout << "err:" << e.what() << "\n";
    }
    return 0;
}
