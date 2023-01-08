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
void *Transformer::visitVarDecl(VarDecl *node, void *arg){
    node->decl = (VarDeclExpr*)node->decl->accept(this, nullptr);
    return node;
}
void *Transformer::visitVarDeclExpr(VarDeclExpr *node, void *arg){
    for(int i=0;i<node->list.size();i++){
        node->list[i]=visit(node->list[i], this);
    }
    return node;
}

void *Transformer::visitObjExpr(ObjExpr *node, void *arg){
    node->type=visit(node->type, this);
    for(auto &e:node->entries){
        e.value = visit(e.value, this);
    }
    return node;
}

void *Transformer::visitFragment(Fragment *node, void *arg){
    if(node->type) node->type = visit(node->type, this);
    node->rhs = visit(node->rhs, this);
    return node;
}

void *Transformer::visitMethodCall(MethodCall *node, void *arg){
    for(int i=0;i<node->typeArgs.size();i++){
        node->typeArgs[i]=visit(node->typeArgs[i], this);
    }
    return node;
}