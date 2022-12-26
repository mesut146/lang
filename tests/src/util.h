#pragma once

#include <cstdarg>
#include <string>
#include <iostream>
#include <string>
#include <vector>
#include <cassert>

static std::string format(const std::string &str,
                          std::vector<std::string> args) {
  std::string result;
  result.reserve(str.size());

  std::string::size_type prev_pos = 0, pos = 0;
  int count = 0;
  while ((pos = str.find("{}", pos)) != std::string::npos) {
    result += str.substr(prev_pos, pos - prev_pos);
    result += args[count++];
    pos += 2;
    prev_pos = pos;
  }

  result += str.substr(prev_pos);
  return result;
}

/*static std::string format(const std::string &str...) {
  std::string result;
  return result;
}*/

static void print(const char* fmt...){
    std::vector<std::string> vec;
    std::va_list args;
    va_start(args, fmt);
    for (int i = 0; i < 1; ++i) {
        auto  a= va_arg(args, const char*);
        vec.push_back(a);
    }
    va_end(args);
    std::cout << format(fmt, vec);
}