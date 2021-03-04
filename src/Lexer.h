#pragma once

#include <fstream>
#include <sstream>
#include <map>
#include "Token.h"

class Lexer{
public:
  std::string buf;
  int pos=0;
  
  Lexer(const std::string& path){
    std::fstream stream;
    stream.open(path, std::fstream::in);
    std::stringstream ss;
    ss<<stream.rdbuf();
    stream.close();
    buf = ss.str();
  }
  
  char peek(){
    return buf[pos];
  }
  
  char read(){
    return buf[pos++];
  }
  
  std::string str(int a,int b){
    return buf.substr(a, b-a+1);
  }
  
  std::string eat(std::string end){
    char c;
    int a;
    return str(a,pos);
  }
  
  Token next();
  Token readNumber();
  Token readIdent();
  Token lineComment();
};
