#include "Compiler.h"
#include "Resolver.h"
#include "parser/Parser.h"
#include "parser/Util.h"
#include <cstring>
#include <filesystem>
#include <functional>
#include <iostream>


bool Config::verbose = true;
bool Config::rvo_ptr = false;
bool Config::debug = true;
bool Config::use_cache = true;

std::string Config::root = "../tests";

std::vector<std::string> list_files(const std::string &dir) {
    std::vector<std::string> res;
    for (const auto &e : std::filesystem::directory_iterator(dir)) {
        if (e.is_directory()) continue;
        if (e.path().extension() != ".x") continue;
        res.push_back(e.path().string());
    }
    return res;
}

DirCompiler get_compiler() {
    DirCompiler dc;
    dc.out_dir = "./out";
    return dc;
}

void build_std() {
    Config::use_cache = true;
    DirCompiler dc = get_compiler();
    dc.compileAll(Config::root + "/std", Config::root);
    dc.build_library("std.a", false);
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

std::string get_bin_name(const std::string &file) {
    auto pos = file.find_last_of('/');
    auto xpos = file.find_last_of(".x");
    int len = xpos - pos - 2;
    return file.substr(pos + 1, len) + ".bin";
}

void compileTest(bool std_test) {
    //clean();
    //Cache::delete_cache();
    if (std_test) {
        build_std();
        //std tests
        Config::use_cache = false;
        for (auto file : list_files(Config::root + "/std_test")) {
            DirCompiler dc = get_compiler();
            dc.compile_single(file, Config::root);
            dc.link_run(get_bin_name(file), dc.out_dir + "/std.a");
        }
    } else {
        Config::use_cache = false;
        for (auto file : list_files(Config::root + "/normal")) {
            DirCompiler dc = get_compiler();
            dc.compile_single(file, Config::root);
            dc.link_run(get_bin_name(file), "");
        }
    }
}

void bootstrap(bool run) {
    //clean();
    DirCompiler dc = get_compiler();
    std::string bin_name = "x";
    bool std_static = true;
    if (std_static) {
        build_std();
        dc.compileAll(Config::root + "/parser", Config::root);
        dc.link(bin_name, dc.out_dir + "/std.a libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++");
    } else {
        dc.compileAll(Config::root + "/std", Config::root);
        dc.compileAll(Config::root + "/parser", Config::root);
        dc.link(bin_name, "libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++");
    }
    auto from = dc.out_dir + "/" + bin_name;
    auto to = "./" + bin_name;
    fs::copy_file(from, to, fs::copy_options::overwrite_existing);
    if (run) {
        dc.run();
    }
}

void ownership() {
    auto common = Config::root + "/own/common.x";
    auto path = Config::root + "/own";
    Config::use_cache = false;
    for (auto &file : list_files(path)) {
        if (!file.ends_with("common.x")) {
            DirCompiler dc = get_compiler();
            dc.compile(common, Config::root);
            dc.compile(file, Config::root);
            auto name = std::filesystem::path(file).filename().string() + ".bin";
            print("##running " + name);
            dc.link_run(name, "");
        }
    };
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
            Cache::delete_cache();
            ++i;
            argc--;
        }
        //no arg
        if (argc == 0) {
            bootstrap(true);
            return 0;
        }
        auto arg = std::string(args[i]);
        ++i;
        if (arg == "help") {
            usage();
        } else if (arg == "bt") {
            bootstrap(false);
        } else if (arg == "test") {
            compileTest(false);
        } else if (arg == "test2") {
            compileTest(true);
        } else if (arg == "std") {
            build_std();
        } else if (arg == "own") {
            ownership();
        } else if (arg == "c") {
            auto path = std::string(args[i]);
            i++;
            bool use_std = false;
            if (path == "-std") {
                use_std = true;
                path = std::string(args[i]);
                i++;
            }
            DirCompiler dc = get_compiler();
            if (std::filesystem::is_directory(path)) {
                dc.compileAll(path, Config::root);
            } else {
                Config::use_cache = false;
                dc.compile(path, Config::root);
                //more files
                for (; i <= argc;) {
                    auto path2 = args[i];
                    dc.compile(path2, Config::root);
                    ++i;
                }
                if (use_std) {
                    dc.compileAll(Config::root + "/std", Config::root);
                }
                if (dc.main_file.has_value()) {
                    dc.link_run("", "");
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
