#include "Compiler.h"
#include "Resolver.h"
#include "parser/Parser.h"
#include "parser/Util.h"
#include <cstring>
#include <filesystem>
#include <iostream>


bool Config::verbose = true;
bool Config::rvo_ptr = false;
bool Config::debug = true;
bool Config::use_cache = true;

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
        c.link_run("");
    } else {
        c.compile(path);
        c.link_run("");
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
    c.link_run("");
}

void clean() {
    for (const auto &e : std::filesystem::directory_iterator(".")) {
        if (e.is_directory()) continue;
        auto ext = e.path().extension().string();
        if (ext == ".ll" /*|| ext == ".o"*/) {
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
    //compile({"../tests/src/virt.x", s1, s2, op});
    //compile({"../tests/src/virt2.x", s1, s2, op});
    compile({"../tests/src/base.x", s1, s2, op});
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
    std::vector<std::string> list{
            "../tests/src/std/String.x",
            "../tests/src/std/str.x",
            "../tests/src/std/ops.x",
            "../tests/src/std/libc.x",
            "../tests/src/std/io.x",
            "../tests/src/parser/token.x",
            "../tests/src/parser/lexer.x",
            "../tests/src/parser/ast.x",
            "../tests/src/parser/printer.x",
            "../tests/src/parser/parser.x",
            "../tests/src/parser/resolver.x",
            "../tests/src/parser/method_resolver.x",
            "../tests/src/parser/utils.x",
            "../tests/src/parser/copier.x",
            "../tests/src/parser/bridge.x",
            "../tests/src/parser/compiler.x",
            "../tests/src/parser/compiler_helper.x",
            "../tests/src/parser/test.x"};
    Compiler c;
    c.srcDir = "../tests/src";
    c.outDir = "../out";
    c.init();
    for (auto &file : list) {
        c.compile(file);
    }
    c.link_run("libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++");
}

void build_std() {
    auto s1 = "../tests/src/std/String.x";
    auto s2 = "../tests/src/std/str.x";
    auto op = "../tests/src/std/ops.x";
    auto libc = "../tests/src/std/libc.x";
    auto io = "../tests/src/std/io.x";
    std::vector<std::string> list{s1, s2, op, libc, io};

    Compiler c;
    c.srcDir = "../tests/src";
    c.outDir = "../out";
    c.init();
    for (auto &file : list) {
        c.compile(file);
    }
    c.build_library("std.a", false);
}

void bridge() {
    auto b = "../tests/src/parser/bridge.x";
    Compiler c;
    c.srcDir = "../tests/src";
    c.outDir = "../out";
    c.init();
    c.compile(b);

    c.build_library("xbridge.a", false);
}

void usage() {
    throw std::runtime_error("usage: ./lang <cmd>\n");
}

int main(int argc, char **args) {
    try {
        argc--;
        int i = 1;
        if (argc > 0 && std::string(args[i]) == "-nc") {
            Config::use_cache = false;
            ++i;
            argc--;
        }
        //no arg
        if (argc == 0) {
            //compileTest();
            bootstrap();
            return 0;
        }
        auto arg = std::string(args[i]);
        ++i;
        if (arg == "help") {
            usage();
        } else if (arg == "parse") {
            parseTest();
        } else if (arg == "test") {
            compileTest();
        } else if (arg == "std") {
            build_std();
        } else if (arg == "br") {
            bridge();
        } else if (arg == "c") {
            auto path = std::string(args[i]);
            i++;
            Compiler c;
            c.srcDir = "../tests/src";
            if (std::filesystem::is_directory(path)) {
                //c.srcDir = path;
                if (argc - 1 == 3) {
                    auto file = path + "/" + std::string(args[i]);
                    i++;
                    c.init();
                    c.compile(file);
                } else {
                    c.compileAll();
                }
            } else {
                Config::use_cache = false;
                c.init();
                c.compile(path);
                if (c.main_file.has_value()) {
                    c.link_run("");
                }
            }
        } else {
            std::cerr << "invalid cmd: " << arg << std::endl;
            usage();
        }
    } catch (std::exception &e) {
        std::cout << "err: " << e.what() << "\n";
    }
    return 0;
}
