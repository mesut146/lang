#pragma once

#include "parser/Ast.h"

struct Ownership {
    Method *method;
    std::vector<Fragment> moved;

    void doMove(Expression *lhs, Expression *rhs);

    //send(expr) //moves expr
    void doMoveCall(Expression *expr);

    void doMoveReturn(Expression *expr);


    bool isMoved(const std::string& name);


    bool needDrop();
};