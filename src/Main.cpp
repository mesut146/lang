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

void delete_cache() {
    if (fs::exists(Cache::CACHE_FILE)) {
        fs::remove(Cache::CACHE_FILE);
    }
}

void compile(const std::string &path) {
    Compiler c;
    c.srcDir = Config::root;
    c.outDir = "../out";
    c.init();
    if (std::filesystem::is_directory(path)) {
        for (const auto &e : std::filesystem::recursive_directory_iterator(path)) {
            if (e.is_directory()) continue;
            if (e.path().extension() != "x") continue;
            c.compile(e.path().string());
        }
    } else {
        c.compile(path);
    }
    c.link_run("", "");
}

void list_dir(const std::string &path, std::function<void(const std::string &)> &f) {
    for (const auto &e : std::filesystem::recursive_directory_iterator(path)) {
        if (e.is_directory()) continue;
        if (e.path().extension() != ".x") continue;
        f(e.path().string());
    }
}

void build_std() {
    //delete_cache();
    Compiler c;
    c.srcDir = Config::root;
    c.outDir = "../out";
    c.init();
    std::function<void(const std::string &)> f = [&](const std::string &file) {
        c.compile(file);
    };
    list_dir(Config::root + "/std", f);
    c.build_library("std.a", false);
}

void compile(std::initializer_list<std::string> list) {
    Compiler c;
    c.srcDir = Config::root;
    c.outDir = "../out";
    c.init();
    for (auto &file : list) {
        c.compile(file);
    }
    c.link_run("", "");
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
    delete_cache();

    Compiler c;
    c.srcDir = Config::root;
    c.outDir = "../out";
    c.init();
    std::function<void(const std::string &)> f = [&](const std::string &file) {
        c.compile(file);
        c.link_run("", "");
    };
    list_dir(Config::root + "/normal", f);

    //std tests
    build_std();
    std::function<void(const std::string &)> f2 = [&](const std::string &file) {
        c.compile(file);
        c.link_run("", "std.a");
    };
    list_dir(Config::root + "/std_test", f2);
}

void bootstrap() {
    clean();
    Compiler c;
    c.srcDir = Config::root;
    c.outDir = "../out";
    c.init();
    std::function<void(const std::string &)> f = [&](const std::string &file) {
        c.compile(file);
    };
    list_dir(Config::root + "/parser", f);

    build_std();

    c.link_run("", "std.a libbridge.a /usr/lib/llvm-16/lib/libLLVM.so -lstdc++");
}

void ownership() {
    auto common = Config::root + "/own/common.x";
    auto path = Config::root + "/own";
    Config::use_cache = false;
    std::function<void(const std::string &)> f = [&](const std::string &file) {
        if (!file.ends_with("common.x")) {
            Compiler c;
            c.srcDir = Config::root;
            c.outDir = "../out";
            c.init();
            c.compile(common);
            c.compile(file);
            auto name = std::filesystem::path(file).filename().string() + ".bin";
            print("##running " + name);
            c.link_run(name, "");
        }
    };
    list_dir(path, f);
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
            delete_cache();
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
        } else if (arg == "test") {
            compileTest();
        } else if (arg == "std") {
            build_std();
        } else if (arg == "own") {
            ownership();
        } else if (arg == "c") {
            auto path = std::string(args[i]);
            i++;
            Compiler c;
            c.srcDir = Config::root;
            //single file in dir
            if (std::filesystem::is_directory(path)) {
                //c.srcDir = path;
                if (i <= argc) {
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
                if (i <= argc) {
                    auto path2 = args[i];
                    ++i;
                    c.compile(path2);
                }
                if (c.main_file.has_value()) {
                    c.link_run("", "");
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
