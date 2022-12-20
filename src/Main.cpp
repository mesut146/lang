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

void parse(const std::string &path, bool print = true) {
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

class Node {
public:
    int val;
    Node *next = nullptr;

    static Node make() {
        auto node = Node{.val = 5};
        auto next = new Node{.val = 6};
        auto next2 = new Node{.val = 7};
        node.next = next;
        next->next = next2;
        return node;
    }

    void print() {
        std::cout << val;
        if (next != nullptr) {
            std::cout << ", ";
            next->print();
        } else {
            std::cout << std::endl;
        }
    }
};

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
            //parse("../tests/exprs");
            //parse("../tests/Optional");
            //parse("../tests/stmts");
            parse("../tests/types");
        }
    } catch (std::exception &e) {
        std::cout << "err:" << e.what() << "\n";
    }
    return 0;
}
