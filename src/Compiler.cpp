#include "Compiler.h"
#include "Resolver.h"
#include "parser/Ast.h"
#include "parser/Parser.h"
#include <filesystem>
#include <iostream>
#include <unordered_map>

#include <llvm/IR/IRBuilder.h>
#include <llvm/IR/LLVMContext.h>
#include <llvm/IR/Value.h>

namespace fs = std::filesystem;

using namespace llvm;

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

static std::unique_ptr<llvm::LLVMContext> TheContext;
static std::unique_ptr<llvm::Module> TheModule;
static std::unique_ptr<llvm::IRBuilder<>> Builder;
static std::map<std::string, llvm::Value *> NamedValues;


static void InitializeModule() {
    // Open a new context and module.
    TheContext = std::make_unique<LLVMContext>();
    TheModule = std::make_unique<Module>("my cool jit", *TheContext);

    // Create a new builder for the module.
    Builder = std::make_unique<IRBuilder<>>(*TheContext);
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
    InitializeModule();
    for (auto m : unit->methods) {
        std::vector<llvm::Type *> Doubles(0, llvm::Type::getDoubleTy(*TheContext));
        FunctionType *FT =
                FunctionType::get(llvm::Type::getDoubleTy(*TheContext), Doubles, false);
        Function *f = Function::Create(FT, llvm::Function::ExternalLinkage, m->name, TheModule.get());

    }
    //TheModule->print(,nullptr);
    TheModule->dump();
}