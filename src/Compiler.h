#pragma once

#include "BaseVisitor.h"
#include <fstream>
#include <string>

struct Compiler {
    std::string srcDir;
    std::string outDir;
    Unit *unit;

    void compileAll();

    void compile(const std::string &path);
};