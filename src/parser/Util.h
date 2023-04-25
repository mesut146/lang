#pragma once

#include "Ast.h"
#include <iostream>
#include <string>
#include <vector>

static bool debug = false;


template<class T>
std::string join(std::vector<T> &arr, const char *sep, const char *indent = "") {
    std::string s;
    for (int i = 0; i < arr.size(); i++) {
        s.append(indent);
        s.append(arr[i].print());
        if (i < arr.size() - 1)
            s.append(sep);
    }
    return s;
}

template<class T>
std::string join(std::vector<T *> &arr, const char *sep, const char *indent = "") {
    std::string s;
    for (int i = 0; i < arr.size(); i++) {
        s.append(indent);
        s.append(arr[i]->print());
        if (i < arr.size() - 1)
            s.append(sep);
    }
    return s;
}

template<class T>
std::string joinPtr(std::vector<T> &arr, const char *sep, const char *indent = "") {
    std::string s;
    for (int i = 0; i < arr.size(); i++) {
        s.append(indent);
        s.append(arr[i]->print());
        if (i < arr.size() - 1)
            s.append(sep);
    }
    return s;
}


std::string join(std::vector<std::string> &arr, const char *sep, const char *indent = "");

void printBody(std::string &buf, Statement *stmt);

void printBody(std::string &buf, Block *block);

void printIdent(std::string &&str, std::string &buf);

void log(const char *msg);
void log(const std::string &msg);
void info(const std::string &msg);

template<typename... Args>
std::string format(const std::string &format, Args... args) {
    int size_s = std::snprintf(nullptr, 0, format.c_str(), args...) + 1;// Extra space for '\0'
    if (size_s <= 0) { throw std::runtime_error("Error during formatting."); }
    auto size = static_cast<size_t>(size_s);
    std::unique_ptr<char[]> buf(new char[size]);
    std::snprintf(buf.get(), size, format.c_str(), args...);
    return std::string(buf.get(), buf.get() + size - 1);// We don't want the '\0' inside
}
