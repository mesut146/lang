#include "Transformer.h"

template <class T>
T visit(T arg, Transformer* t){
    return (T)arg->accept(t, nullptr);
}

void* Transformer::visitLiteral(Literal *lit, A arg){
    return lit;
}
R Transformer::visitSimpleName(SimpleName *sn, A arg){
    return sn;
}
void* Transformer::visitBlock(Block *b, A arg){
    for(int i=0;i<b->list.size();i++){
        b->list[i]=(Statement*)b->list[i]->accept(this, nullptr);
    }
    return b;
}

R Transformer::visitReturnStmt(ReturnStmt *r, A arg){
    if(r->expr)
      r->expr=visit(r->expr, this);
    return r;
}

R Transformer::visitInfix(Infix *i, A arg){
    i->left=visit(i->left, this);
    i->right=visit(i->right, this);
    return i;
}

R Transformer::visitType(Type *type, A arg){
    return type;
}