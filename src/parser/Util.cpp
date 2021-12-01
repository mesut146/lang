#include "Util.h"

bool debug = false;

void log(const char *msg) {
    if (debug)
        std::cout << msg << std::endl;
}

void log(const std::string &msg) {
    if (debug)
        std::cout << msg << std::endl;
}

std::string join(std::vector<std::string> &arr, const char *sep, const char *indent) {
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
    auto i = 0;
    for (Statement *statement : block->list) {
        printBody(buf, statement);
        if (i < block->list.size() - 1)
            buf.append("\n");
        i++;
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

void printIdent(std::string &&str, std::string &buf) {
    int start = 0;
    auto end = str.find('\n');
    while (end != std::string::npos) {
        std::string line = str.substr(start, end - start);
        buf.append("    ").append(line).append("\n");
        start = end + 1;
        end = str.find('\n', start);
    }
    std::string line = str.substr(start, end - start);
    buf.append("    ").append(line).append("\n");
}
