#include "bridge.h"


extern "C" {

int getDefaultTargetTriple(char *ptr) {
    std::string res = llvm::sys::getDefaultTargetTriple();
    memcpy(ptr, res.data(), res.length());
    return res.length();
}


}