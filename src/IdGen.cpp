#include "IdGen.h"
#include "Resolver.h"


void *IdGen::visitInfix(Infix *node) {
    return nullptr;
}

void *IdGen::visitMethodCall(MethodCall *node) {
    auto id = mangle(resolver->curMethod) + "#" + node->print();
    return new std::string(id);
}

void *IdGen::visitSimpleName(SimpleName *node) {
    auto id = mangle(resolver->curMethod) + "#" + node->print();
    return new std::string(id);
}
void *IdGen::visitLiteral(Literal *node) {
    return nullptr;
}
void *IdGen::visitRefExpr(RefExpr *node) {
    return nullptr;
}
void *IdGen::visitType(Type *node) {
    return nullptr;
}
void *IdGen::visitObjExpr(ObjExpr *node) {
    auto id = mangle(resolver->curMethod) + "#" + node->print();
    return new std::string(id);
}
void *IdGen::visitFieldAccess(FieldAccess *node) {
    return nullptr;
}
void *IdGen::visitDerefExpr(DerefExpr *node) {
    return nullptr;
}
void *IdGen::visitParExpr(ParExpr *node) {
    return nullptr;
}
void *IdGen::visitUnary(Unary *node) {
    return nullptr;
}
void *IdGen::visitArrayAccess(ArrayAccess *node) {
    return nullptr;
}

void *IdGen::visitArrayExpr(ArrayExpr *node) {
    return nullptr;
}
void *IdGen::visitAsExpr(AsExpr *node) {
    return nullptr;
}