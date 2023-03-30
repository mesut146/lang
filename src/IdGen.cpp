#include "IdGen.h"
#include "Resolver.h"

std::any IdGen::get(Expression *node) {
    if (resolver->curMethod) {
        return printMethod(resolver->curMethod) + "#" + node->print();
    }
    return {};
}


std::any IdGen::visitInfix(Infix *node) {
    return get(node);
}
std::any IdGen::visitAssign(Assign *node) {
    return {};
}

std::any IdGen::visitMethodCall(MethodCall *node) {
    auto id = printMethod(resolver->curMethod) + "#" + node->print();
    return id;
}

std::any IdGen::visitSimpleName(SimpleName *node) {
    auto id = printMethod(resolver->curMethod) + "#" + node->print();
    return id;
}
std::any IdGen::visitLiteral(Literal *node) {
    return {};
}
std::any IdGen::visitRefExpr(RefExpr *node) {
    return {};
}
std::any IdGen::visitType(Type *node) {
    return get(node);
}
std::any IdGen::visitObjExpr(ObjExpr *node) {
    auto id = printMethod(resolver->curMethod) + "#" + node->print();
    return id;
}
std::any IdGen::visitFieldAccess(FieldAccess *node) {
    return get(node);
}
std::any IdGen::visitDerefExpr(DerefExpr *node) {
    return {};
}
std::any IdGen::visitParExpr(ParExpr *node) {
    return {};
}
std::any IdGen::visitUnary(Unary *node) {
    return {};
}
std::any IdGen::visitArrayAccess(ArrayAccess *node) {
    return {};
}

std::any IdGen::visitArrayExpr(ArrayExpr *node) {
    return {};
}
std::any IdGen::visitAsExpr(AsExpr *node) {
    return {};
}
std::any IdGen::visitIsExpr(IsExpr *node) {
    return {};
}