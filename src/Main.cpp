#include "Compiler.h"
#include "Resolver.h"
#include "parser/Parser.h"
#include "parser/Util.h"
#include <cstring>
#include <iostream>

void lex(std::string &path) {
    Lexer lexer(path);

    for (;;) {
        Token &t = *lexer.next();
        if (t.is(EOF_))
            break;
        printf("type=%d off=%d val='%s'\n", t.type, t.start, t.value.c_str());
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

void resolveTest() {
    debug = false;
    //std::string path="../tests/resolve1";
    //std::string path="../tests/resolveClass";
    //std::string path="../tests/arrow";
    std::string path = "../tests/importTest";
    //std::string path="../tests/a";
    //std::string path="../tests/core/List";
    auto root = "../tests";
    Resolver *r = Resolver::getResolver(path, root);
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

void compile() {
    Compiler c;
    c.srcDir = "../tests/src";
    c.outDir = "../out";
    c.compileAll();
}

void parseTest() {
    debug = true;
    parse("../tests/exprs");
    parse("../tests/stmts");
    parse("../tests/types");
    parse("../tests/core/Array");
    parse("../tests/core/Optional");
    parse("../tests/core/String");
    parse("../tests/core/List");
    parse("../tests/src/a.x", true);
}

int main(int argc, char **args) {
    try {
        if (argc == 1) {
            compile();
            return 0;
        }
        auto arg = std::string(args[1]);
        if (arg == "parse") {
            parseTest();
        } else if (arg == "resolve") {
            resolveTest();
        } else {
            std::cerr << "invalid cmd: " << arg;
        }
    } catch (std::exception &e) {
        std::cout << "err:" << e.what() << "\n";
    }
    return 0;
}
