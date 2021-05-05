#pragma once

#include <string>
#include <vector>
#include <iostream>

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

std::string join(std::vector<std::string> &arr, const char *sep, const char *indent = "") {
  std::string s;
  for (int i = 0; i < arr.size(); i++) {
    s.append(indent);
    s.append(arr[i]);
    if (i < arr.size() - 1)
      s.append(sep);
  }
  return s;
}
void printBody(std::string &buf, Statement *stmt);

void printBody(std::string &buf, Block *block) {
  buf.append("{\n");
  for (Statement *statement : block->list) {
    printBody(buf, statement);
  }
  buf.append("}");
}

void printBody(std::string &buf, Statement *stmt) {
  Block *b = dynamic_cast<Block *>(stmt);
  if (b == nullptr) {
    buf.append("\n  ").append(stmt->print());
  } else {
    printBody(buf, b);
  }
}


void printBody(std::string &buf, const std::string &to) {
  auto pos = to.find('\n');
  while (pos != std::string::npos) {
    buf.append("  ").append(to.substr(0, pos));
    auto tmp = to.find('\n');
    if (tmp == std::string::npos) {
      buf.append("  ").append(to.substr(pos));
      break;
    } else {
      pos = tmp;
    }
  }
}

bool debug = false;

void log(const char *msg) {
  if (debug)
    std::cout << msg << "\n";
}

void log(const std::string &msg) {
  if (debug)
    std::cout << msg << "\n";
}
