#include "Compiler.h"
#include "Resolver.h"
#include "parser/Parser.h"
#include "parser/Util.h"
#include <cstring>
#include <filesystem>
#include <iostream>

void lex(std::string &path) {
    Lexer lexer(path);

    for (;;) {
        auto t = lexer.next();
        if (t.is(EOF_))
            break;
        printf("type=%d off=%d val='%s'\n", t.type, t.start, t.value.c_str());
    }
}

void parse(const std::string &path, bool print = false) {
    info("parsing " + path);
    Lexer lexer(path);
    Parser parser(lexer);
    auto u = parser.parseUnit();
    if (print) {
        std::cout << u->print() << "\n";
    }
}

void parseTest() {
    debug = true;
    auto path = "../tests/parser";
    for (auto &file : std::filesystem::directory_iterator(path)) {
        auto file_path = "./tests/" + file.path().string();
        parse(file_path);
    }
}

void compile(const std::string &path) {
    Compiler c;
    c.srcDir = "../tests/src";
    c.outDir = "../out";
    c.init();
    if (std::filesystem::is_directory(path)) {
        for (const auto &e : std::filesystem::recursive_directory_iterator(path)) {
            if (e.is_directory()) continue;
            c.compile(e.path().string());
        }
        c.link_run();
    } else {
        c.compile(path);
        c.link_run();
    }
}

void compile(std::initializer_list<std::string> list) {
    Compiler c;
    c.srcDir = "../tests/src";
    c.outDir = "../out";
    c.init();
    for (auto &file : list) {
        c.compile(file);
    }
    c.link_run();
}

void clean() {
    for (const auto &e : std::filesystem::directory_iterator(".")) {
        if (e.is_directory()) continue;
        auto ext = e.path().extension().string();
        if (ext == ".ll" || ext == ".o") {
            std::filesystem::remove(e.path());
        }
    }
}

void compileTest() {
    clean();

    auto s1 = "../tests/src/std/String.x";
    auto s2 = "../tests/src/std/str.x";
    auto op = "../tests/src/std/ops.x";
    auto libc = "../tests/src/std/libc.x";
    auto io = "../tests/src/std/io.x";

    //compile("../tests/src/opaq.x");
    //compile("../tests/src/dbg.x");

    compile("../tests/src/lit.x");
    compile("../tests/src/var.x");
    compile("../tests/src/infix.x");
    compile("../tests/src/flow.x");
    compile("../tests/src/pass.x");
    compile("../tests/src/ret.x");
    compile("../tests/src/alloc.x");
    compile("../tests/src/array.x");
    compile("../tests/src/importTest");
    compile("../tests/src/traits.x");
    compile("../tests/src/generic.x");
    compile("../tests/src/structTest.x");
    compile("../tests/src/enumTest.x");
    compile("../tests/src/malloc.x");
    compile("../tests/src/impl.x");
    compile("../tests/src/load.x");
    compile("../tests/src/as.x");
    compile("../tests/src/alias.x");

    //std tests
    compile({"../tests/src/classTest.x", s1, s2, op});
    compile({"../tests/src/boxTest.x", s1, s2, op});
    compile({"../tests/src/listTest.x", s1, s2, op});
    compile({"../tests/src/strTest.x", s1, s2, op});
    compile({"../tests/src/opt.x", s1, s2, op});
    compile({"../tests/src/mapTest.x", s1, s2, op});
    compile({"../tests/src/libc-test.x", s1, s2, op, libc, io});

    //compile({"../tests/src/bug1.x", s1, s2, op, libc, io});
}

void bootstrap() {
    clean();
    auto s1 = "../tests/src/std/String.x";
    auto s2 = "../tests/src/std/str.x";
    auto op = "../tests/src/std/ops.x";
    auto libc = "../tests/src/std/libc.x";
    auto io = "../tests/src/std/io.x";
    auto tok = "../tests/src/parser/token.x";
    auto lx = "../tests/src/parser/lexer.x";
    auto ast = "../tests/src/parser/ast.x";
    auto printer = "../tests/src/parser/printer.x";
    auto ps = "../tests/src/parser/parser.x";
    auto rs = "../tests/src/parser/resolver.x";
    auto mr = "../tests/src/parser/method_resolver.x";
    compile({"../tests/src/parser/test.x", s1, s2, op, tok, libc, io, lx, ast, printer, ps, rs, mr});
}

void usage() {
    throw std::runtime_error("usage: ./lang <cmd>\n");
}

int main(int argc, char **args) {
    try {
        //no arg
        if (argc == 1) {
            //compileTest();
            bootstrap();
            return 0;
        }
        auto arg = std::string(args[1]);
        if (arg == "help") {
            usage();
        } else if (arg == "parse") {
            parseTest();
        } else if (arg == "c") {
            auto file = std::string(args[2]);
            Compiler c;
            if (std::filesystem::is_directory(file)) {
                c.srcDir = file;
                c.compileAll();
            } else {
                c.init();
                c.compile(file);
            }
        } else {
            std::cerr << "invalid cmd: " << arg << std::endl;
            usage();
        }
    } catch (std::exception &e) {
        std::cout << "err:" << e.what() << "\n";
    }
    return 0;
}
