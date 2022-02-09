#include "Visitor.h"

template <class R, class A>
class BaseVisitor : public Visitor<R, A>{
public:

    virtual R visitBlock(Block *, A arg) ;

    virtual R visitImportStmt(ImportStmt *, A arg) ;

    virtual R visitMethod(Method *, A arg) ;

    virtual R visitExprStmt(ExprStmt *, A arg) ;

    virtual R visitLiteral(Literal* lit, A arg) ;

    virtual R visitSimpleName(SimpleName* sn, A arg) ;

    virtual R visitQName(QName* qn, A arg) ;

    virtual R visitSimpleType(SimpleType* sn, A arg) ;

    virtual R visitRefType(RefType* sn, A arg) ;
    
    virtual R visitVarDecl(VarDecl *, A arg) ;

    virtual R visitVarDeclExpr(VarDeclExpr *, A arg) ;

    virtual R visitUnary(Unary *, A arg) ;

    virtual R visitAssign(Assign *, A arg) ;

    virtual R visitInfix(Infix *, A arg) ;

    virtual R visitPostfix(Postfix *, A arg) ;

    virtual R visitTernary(Ternary *, A arg) ;

    virtual R visitMethodCall(MethodCall *, A arg) ;

    virtual R visitFieldAccess(FieldAccess *, A arg) ;

    virtual R visitArrayAccess(ArrayAccess *, A arg) ;

    virtual R visitArrayExpr(ArrayExpr *, A arg) ;

    virtual R visitParExpr(ParExpr *, A arg) ;

    virtual R visitArrowFunction(ArrowFunction* sn, A arg) ;

    virtual R visitObjExpr(ObjExpr *, A arg) ;

    virtual R visitAnonyObjExpr(AnonyObjExpr *, A arg) ;

    virtual R visitReturnStmt(ReturnStmt *, A arg) ;

    virtual R visitContinueStmt(ContinueStmt *, A arg) ;

    virtual R visitBreakStmt(BreakStmt *, A arg) ;

    virtual R visitIfStmt(IfStmt *, A arg) ;

    virtual R visitWhileStmt(WhileStmt *, A arg) ;

    virtual R visitDoWhile(DoWhile *, A arg) ;

    virtual R visitForStmt(ForStmt *, A arg) ;

    virtual R visitForEach(ForEach *, A arg) ;

    virtual R visitTryStmt(TryStmt* sn, A arg) ;

    virtual R visitThrowStmt(ThrowStmt* sn, A arg) ;

    virtual R visitCatchStmt(CatchStmt* sn, A arg) ;

};