#include "Compiler.h"
#include "Resolver.h"
#include "parser/Ast.h"
#include "parser/Parser.h"
#include <filesystem>
#include <iostream>
#include <unordered_map>

namespace fs = std::filesystem;

std::string getName(const std::string &path) {
    auto i = path.rfind('/');
    return path.substr(i + 1);
}

void Compiler::compileAll() {
    for (const auto &e : fs::recursive_directory_iterator(srcDir)) {
        if (e.is_directory()) continue;
        compile(e.path().string());
    }
}

void Compiler::compile(const std::string &path) {
    auto name = getName(path);
    if (path.rfind(".x") == std::string::npos) {
        //copy res
        std::ifstream src;
        src.open(path, src.binary);
        std::ofstream trg;
        trg.open(outDir + "/" + name, trg.binary);
        trg << src.rdbuf();
        return;
    }
    std::cout << "compiling " << path << std::endl;
    Lexer lexer(path);
    Parser parser(lexer);
    unit = parser.parseUnit();
    //todo
}