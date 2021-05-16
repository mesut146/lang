#pragma once

#include "Ast.h"
#include <iostream>
#include <string>
#include <vector>


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


std::string join(std::vector<std::string> &arr, const char *sep, const char *indent = "");

void printBody(std::string &buf, Statement *stmt);

void printBody(std::string &buf, Block *block);

void log(const char *msg);

void log(const std::string &msg);
