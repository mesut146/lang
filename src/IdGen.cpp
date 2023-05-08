#include "IdGen.h"
#include "Resolver.h"

std::any IdGen::get(Expression *node) {
    if (resolver->curMethod) {
        return printMethod(resolver->curMethod) + "#" + std::to_string(resolver->max_scope) + "#" + node->print();
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
    return get(node);
}

std::any IdGen::visitSimpleName(SimpleName *node) {
    return get(node);
}
std::any IdGen::visitLiteral(Literal *node) {
    return {};
}
std::any IdGen::visitRefExpr(RefExpr *node) {
    return {};
}
std::any IdGen::visitType(Type *node) {
    return {};
    //return get(node);
}
std::any IdGen::visitObjExpr(ObjExpr *node) {
    return get(node);
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