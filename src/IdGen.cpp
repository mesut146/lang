#include "IdGen.h"
#include "Resolver.h"


void *IdGen::visitInfix(Infix *node, void *arg) {
    auto id = resolver->curMethod->name + "#" + node->print();
    return new std::string(id);
}

void *IdGen::visitMethodCall(MethodCall *node, void *arg) {
    auto id = resolver->curMethod->name + "#" + node->print();
    return new std::string(id);
}

void *IdGen::visitSimpleName(SimpleName *node, void *arg) {
    auto id = resolver->curMethod->name + "#" + node->print();
    return new std::string(id);
}
void *IdGen::visitLiteral(Literal *node, void *arg) {
    return nullptr;
}
void *IdGen::visitRefExpr(RefExpr *node, void *arg) {
    return nullptr;
}
void *IdGen::visitType(Type *node, void *arg) {
    return nullptr;
}
void *IdGen::visitObjExpr(ObjExpr *node, void *arg) {
    return nullptr;
}
void *IdGen::visitFieldAccess(FieldAccess *node, void *arg) {
    return nullptr;
}
void *IdGen::visitDerefExpr(DerefExpr *node, void *arg) {
    return nullptr;
}
void *IdGen::visitParExpr(ParExpr *node, void *arg) {
    return nullptr;
}
void *IdGen::visitUnary(Unary *node, void *arg) {
    return nullptr;
}
void *IdGen::visitArrayAccess(ArrayAccess *node, void *arg){
    return nullptr;
}