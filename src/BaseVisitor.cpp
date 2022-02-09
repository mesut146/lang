#include "BaseVisitor.h"

     R visitBlock(Block *, A arg) { return nullptr; }

     R visitImportStmt(ImportStmt *, A arg) { return nullptr; }

     R visitMethod(Method *, A arg) { return nullptr; }

     R visitExprStmt(ExprStmt *, A arg) { return nullptr; }

     R visitLiteral(Literal* lit, A arg) { return nullptr; }

     R visitSimpleName(SimpleName* sn, A arg) { return nullptr; }

     R visitQName(QName* qn, A arg) { return nullptr; }

     R visitSimpleType(SimpleType* sn, A arg) { return nullptr; }

     R visitRefType(RefType* sn, A arg) { return nullptr; }
    
     R visitVarDecl(VarDecl *, A arg) { return nullptr; }

     R visitVarDeclExpr(VarDeclExpr *, A arg) { return nullptr; }

     R visitUnary(Unary *, A arg) { return nullptr; }

     R visitAssign(Assign *, A arg) { return nullptr; }

     R visitInfix(Infix *, A arg) { return nullptr; }

     R visitPostfix(Postfix *, A arg) { return nullptr; }

     R visitTernary(Ternary *, A arg) { return nullptr; }

     R visitMethodCall(MethodCall *, A arg) { return nullptr; }

     R visitFieldAccess(FieldAccess *, A arg) { return nullptr; }

     R visitArrayAccess(ArrayAccess *, A arg) { return nullptr; }

     R visitArrayExpr(ArrayExpr *, A arg) { return nullptr; }

     R visitParExpr(ParExpr *, A arg) { return nullptr; }

     R visitArrowFunction(ArrowFunction* sn, A arg) { return nullptr; }

     R visitObjExpr(ObjExpr *, A arg) { return nullptr; }

     R visitAnonyObjExpr(AnonyObjExpr *, A arg) { return nullptr; }

     R visitReturnStmt(ReturnStmt *, A arg) { return nullptr; }

     R visitContinueStmt(ContinueStmt *, A arg) { return nullptr; }

     R visitBreakStmt(BreakStmt *, A arg) { return nullptr; }

     R visitIfStmt(IfStmt *, A arg) { return nullptr; }

     R visitWhileStmt(WhileStmt *, A arg) { return nullptr; }

     R visitDoWhile(DoWhile *, A arg) { return nullptr; }

     R visitForStmt(ForStmt *, A arg) { return nullptr; }

     R visitForEach(ForEach *, A arg) { return nullptr; }

     R visitTryStmt(TryStmt* sn, A arg) { return nullptr; }

     R visitThrowStmt(ThrowStmt* sn, A arg) { return nullptr; }

     R visitCatchStmt(CatchStmt* sn, A arg) { return nullptr; }