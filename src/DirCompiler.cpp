#include "Compiler.h"
#include <llvm/MC/TargetRegistry.h>
#include <llvm/Support/TargetSelect.h>
#include <llvm/Target/TargetOptions.h>
#include <llvm/TargetParser/Host.h>

std::vector<std::string> DirCompiler::global_protos = {};

void Compiler::init_llvm() {
    if (TargetMachine) {
        return;
    }
    TargetTriple = llvm::sys::getDefaultTargetTriple();
    llvm::InitializeAllTargetInfos();
    llvm::InitializeAllTargets();
    llvm::InitializeAllTargetMCs();
    llvm::InitializeAllAsmParsers();
    llvm::InitializeAllAsmPrinters();

    std::string Error;
    //llvm::TargetRegistry::printRegisteredTargetsForVersion(llvm::outs());
    auto Target = llvm::TargetRegistry::lookupTarget(TargetTriple, Error);

    if (!Target) {
        throw std::runtime_error(Error);
    }
    auto CPU = "generic";
    auto Features = "";

    llvm::TargetOptions opt;
    auto RM = std::optional<llvm::Reloc::Model>(llvm::Reloc::Model::PIC_);
    TargetMachine = Target->createTargetMachine(TargetTriple, CPU, Features, opt, RM);
}

void DirCompiler::compile_single(const std::string &file, const std::string &root) {
    skip_main = false;
    compile(file, root);
}
void DirCompiler::compile(const std::string &file, const std::string &root) {
    fs::create_directory(out_dir);
    Context context(root);
    Compiler c(context);
    c.compile(file, *this);
}

void DirCompiler::compileAll(const std::string &srcDir, const std::string &root) {
    skip_main = true;
    cache.read_cache();
    fs::create_directory(out_dir);
    for (const auto &e : fs::recursive_directory_iterator(srcDir)) {
        if (e.is_directory()) continue;
        if (e.path().extension() != ".x") {
            continue;
        }
        Context context(root);
        Compiler c(context);
        c.compile(e.path().string(), *this);
    }
    //compile main file last so that we collect all globals
    if (main_file.has_value()) {
        skip_main = false;
        Context context(root);
        Compiler c(context);
        c.compile(main_file.value(), *this);
        main_file.reset();
    }
    /*for (auto &[k, v] : Resolver::resolverMap) {
        //v.reset();
        //v->unit.reset();
    }*/
}

void DirCompiler::link_run(const std::string &name0, const std::string &args) {
    link(name0, args);
    run();
}

void DirCompiler::link(const std::string &name0, const std::string &args) {
    fs::create_directory(out_dir);
    auto name = name0;
    if (name0.empty()) {
        name = "a.out";
    }
    auto path = out_dir + "/" + name;
    if (fs::exists(path)) {
        fs::remove(path);
        //system(("rm " + path).c_str());
    }
    std::string cmd = "clang-16 -no-pie ";
    cmd.append("-o ").append(path).append(" ");
    for (auto &obj : compiled) {
        cmd.append(obj);
        cmd.append(" ");
    }
    //destroy this
    compiled.clear();
    main_file.reset();
    global_protos.clear();

    cmd.append(args);
    binary_path = path;
    if (system(cmd.c_str()) != 0) {
        print(cmd + "\n");
        throw std::runtime_error("link failed");
    }
}

void DirCompiler::run() {
    auto code = system(binary_path.c_str());
    if (code != 0) {
        print("run failed code = " + std::to_string(code));
        exit(1);
    }
}

void DirCompiler::build_library(const std::string &name, bool shared) {
    fs::create_directory(out_dir);
    std::string cmd = "";
    auto path = out_dir + "/" + name;
    if (shared) {
        cmd += "clang-16 ";
        cmd += "-shared -o ";
        cmd += path;
    } else {
        cmd += "ar rcs ";
        cmd += path;
    }
    cmd += " ";
    for (auto &obj : compiled) {
        cmd.append(obj);
        cmd.append(" ");
    }
    compiled.clear();
    if (system(cmd.c_str()) == 0) {
        print("build library " + path);
    } else {
        print(cmd + "\n");
        throw std::runtime_error("link failed");
    }
}