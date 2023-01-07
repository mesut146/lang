#include "Transformer.h"

template<class T>
T visit(T arg, Transformer *t) {
    return (T) arg->accept(t, nullptr);
}

void *Transformer::visitLiteral(Literal *lit, void *arg) {
    return lit;
}
void *Transformer::visitSimpleName(SimpleName *sn, void *arg) {
    return sn;
}
void *Transformer::visitBlock(Block *b, void *arg) {
    for (int i = 0; i < b->list.size(); i++) {
        b->list[i] = (Statement *) b->list[i]->accept(this, nullptr);
    }
    return b;
}

void *Transformer::visitReturnStmt(ReturnStmt *r, void * arg) {
    if (r->expr)
        r->expr = visit(r->expr, this);
    return r;
}

void *Transformer::visitInfix(Infix *i, void * arg) {
    i->left = visit(i->left, this);
    i->right = visit(i->right, this);
    return i;
}

void *Transformer::visitType(Type *type, void * arg) {
    return type;
}