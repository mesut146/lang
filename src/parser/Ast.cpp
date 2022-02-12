#include "parser/Ast.h"
#include "parser/Util.h"

std::string Unit::print() {
    std::string s;
    s.append(join(imports, "\n"));
    if (!types.empty()) {
        if (!imports.empty()) s.append("\n\n");
        s.append(join(types, "\n\n"));
    }

    s.append("\n");
    if (!methods.empty()) {
        if (!types.empty()) s.append("\n");
        s.append(join(methods, "\n\n"));
    }
    if (!stmts.empty()) {
        s.append("\n\n");
        s.append(join(stmts, "\n"));
    }
    return s;
}

std::string NamedImport::print() {
    if (as != nullptr) {
        return name + " as " + *as;
    } else {
        return name;
    }
}

std::string ImportStmt::print() {
    std::string s;
    s.append("import ");
    if (isStar) {
        s.append("* ");
        if (as != nullptr) {
            s.append("as ").append(*as);
        }
    } else {
        s.append(join(namedImports, ", "));
    }

    s.append(" from ");
    s.append("\"").append(from).append("\"");
    return s;
}

std::string EnumDecl::print() {
    std::string s;
    s.append("enum ");
    s.append(name);
    s.append("{\n");
    s.append(join(cons, ",\n", "  "));
    s.append("\n}");
    return s;
}

void* EnumDecl::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitEnumDecl(this, arg);
}

std::string TypeDecl::print() {
    std::string s;
    s.append(isInterface ? "interface " : "class ");
    s.append(name);
    if (!typeArgs.empty()) {
        s.append("<").append(join(typeArgs, ", ")).append(">");
    }
    if (!baseTypes.empty()) {
        s.append(" : ").append(join(baseTypes, ", "));
    }
    s.append("{\n");
    for (int i = 0; i < fields.size(); i++) {
        s.append("  ").append(fields[i]->print());
        if (i < fields.size() - 1) s.append("\n");
    }
    if (!methods.empty()) {
        if (!fields.empty()) s.append("\n");
        s.append(join(methods, "\n\n", "  "));
    }
    if (!types.empty()) {
        if (!methods.empty()) s.append("\n");
        s.append(join(types, "\n\n", "  "));
    }
    s.append("\n}");
    return s;
}

void* TypeDecl::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitTypeDecl(this, arg);
}

std::string FieldDecl::print() {
    std::string s;
    s.append(name);
    if (isOptional) {
        s.append("?");
    }
    if (type != nullptr) {
        s.append(": ");
        s.append(type->print());
    }
    if (expr != nullptr) {
        s.append(" = ");
        s.append(expr->print());
    }
    s.append(";");
    return s;
}

std::string Method::print() {
    std::string s;
    s.append("func ");
    s.append(name);
    if (!typeArgs.empty()) {
        s.append("<");
        s.append(join(typeArgs, ","));
        s.append(">");
    }
    s.append("(");
    s.append(join(params, ", "));
    s.append(")");
    if (type != nullptr) {
        s.append(": ");
        s.append(type->print());
    }
    if (body == nullptr) {
        s.append(";");
    } else {
        s.append(body->print());
    }
    return s;
}

bool Name::isSimple(){ return false; }

SimpleName::SimpleName(std::string name) : name(name){}

std::string SimpleName::print() {
    return name;
}

void* SimpleName::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitSimpleName(this, arg);
}

bool SimpleName::isSimple(){ return true; }

QName::QName(Name* scope, std::string name) : scope(scope), name(name){}

std::string QName::print() {
    return scope->print() + "." + name;
}

void* QName::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitQName(this, arg);
}

std::string Literal::print() {
    std::string s;
    s.append(val);
    return s;
}

void* Literal::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitLiteral(this, arg);
}

std::string VarDecl::print() {
    std::string s;
    s.append(isVar ? "var" : "let");
    s.append(" ");
    s.append(join(list, ", "));
    s.append(";");
    return s;
}

void* VarDecl::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitVarDecl(this, arg);
}

std::string VarDeclExpr::print() {
    std::string s;
    s.append(isVar ? "var" : "let");
    s.append(" ");
    s.append(join(list, ", "));
    return s;
}

void* VarDeclExpr::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitVarDeclExpr(this, arg);
}

std::string Fragment::print() {
    std::string s;
    s.append(name);
    if (type != nullptr) {
        s.append(":").append(type->print());
    }
    if (rhs != nullptr) {
        s.append(" = ").append(rhs->print());
    }
    return s;
}

std::string ExprStmt::print() {
    return expr->print() + ";";
}

void* ExprStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitExprStmt(this, arg);
}

std::string Block::print() {
    std::string s;
    s.append("{\n");
    for (int i = 0; i < list.size(); ++i) {
        printIdent(list[i]->print(), s);
    }
    s.append("\n}");
    return s;
}

void* Block::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitBlock(this, arg);
}

std::string dims(Type *type) {
    std::string s;
    for (int i = 0; i < type->arrayLevel; i++) {
        s.append("[]");
    }
    return s;
}

std::string SimpleType::print() {
    return *type + dims(this);
}

void* SimpleType::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitSimpleType(this, arg);
}

std::string RefType::print() {
    std::string s;
    s.append(name->print());
    if (!typeArgs.empty()) {
        s.append("<");
        s.append(join(typeArgs, ", "));
        s.append(">");
    }
    s.append(dims(this));
    return s;
}

void* RefType::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitRefType(this, arg);
}


std::string Param::print() {
    std::string s;
    s.append(name);
    if (isOptional) {
        s.append("?");
    }
    if (type != nullptr) {
        s.append(": ");
        s.append(type->print());
    }

    if (defVal != nullptr) {
        s.append(" = ");
        s.append(defVal->print());
    }
    return s;
}

std::string ArrowFunction::print() {
    std::string s;
    s.append("(");
    s.append(join(params, ", "));
    s.append(")");
    s.append(" => ");
    if (block != nullptr) {
        s.append(block->print());
    } else {
        s.append(expr->print());
    }
    return s;
}

void* ArrowFunction::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitArrowFunction(this, arg);
}

std::string ParExpr::print() {
    return std::string("(" + expr->print() + ")");
}

void* ParExpr::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitParExpr(this, arg);
}

std::string ObjExpr::print() {
    std::string s;
    s.append(name);
    s.append("{");
    s.append(join(entries, ", "));
    s.append("}");
    return s;
}

void* ObjExpr::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitObjExpr(this, arg);
}

std::string AnonyObjExpr::print() {
    std::string s;
    s.append("{");
    s.append(join(entries, ", "));
    s.append("}");
    return s;
}

void* AnonyObjExpr::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitAnonyObjExpr(this, arg);
}

std::string Entry::print() {
    return key->print() + ":" + value->print();
}


std::string IfStmt::print() {
    std::string s;
    s.append("if(").append(expr->print()).append(")").append(thenStmt->print());
    if (elseStmt != nullptr) {
        s.append("else ").append(elseStmt->print());
    }
    return s;
}

void* IfStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitIfStmt(this, arg);
}

std::string ForStmt::print() {
    std::string s;
    s.append("for(");
    if (decl != nullptr) {
        s.append(decl->print());
    }
    s.append(";");
    if (cond != nullptr) {
        s.append(cond->print());
    }
    s.append(";");
    if (!updaters.empty()) {
        s.append(join(updaters, ", "));
    }
    s.append(")");
    printBody(s, body);
    return s;
}

void* ForStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitForStmt(this, arg);
}

std::string ForEach::print() {
    std::string s;
    s.append("for(");
    s.append(decl->print());
    s.append(":");
    s.append(expr->print());
    s.append(")\n");
    s.append(body->print());
    return s;
}

void* ForEach::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitForEach(this, arg);
}

std::string Infix::print() {
    return left->print() + " " + op + " " + right->print();
}

void* Infix::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitInfix(this, arg);
}

std::string Assign::print() {
    return left->print() + " " + op + " " + right->print();
}

void* Assign::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitAssign(this, arg);
}

std::string Unary::print() {
    return op + expr->print();
}

void* Unary::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitUnary(this, arg);
}

std::string Postfix::print() {
    return expr->print() + op;
}

void* Postfix::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitPostfix(this, arg);
}

std::string FieldAccess::print() {
    if (isOptional) {
        return scope->print() + "?." + name;
    }
    return scope->print() + "." + name;
}

void* FieldAccess::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitFieldAccess(this, arg);
}

std::string MethodCall::print() {
    if (scope == nullptr) {
        return name + "(" + join(args, ", ") + ")";
    } else {
        if (isOptional) {
            return scope->print() + "?." + name + "(" + join(args, ", ") + ")";
        }
        return scope->print() + "." + name + "(" + join(args, ", ") + ")";
    }
}

void* MethodCall::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitMethodCall(this, arg);
}

std::string ArrayAccess::print() {
    if (isOptional) {
        return array->print() + "?[" + index->print() + "]";
    }
    return array->print() + "[" + index->print() + "]";
}

void* ArrayAccess::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitArrayAccess(this, arg);
}

std::string ArrayExpr::print() {
    return "[" + join(list, ", ") + "]";
}

void* ArrayExpr::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitArrayExpr(this, arg);
}

std::string Ternary::print() {
    return cond->print() + "?" + thenExpr->print() + ":" + elseExpr->print();
}

void* Ternary::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitTernary(this, arg);
}

std::string WhileStmt::print() {
    std::string s;
    s.append("while(").append(expr->print()).append(")");
    printBody(s, body);
    return s;
}

void* WhileStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitWhileStmt(this, arg);
}

std::string ReturnStmt::print() {
    if (expr == nullptr) return "return";
    return "return " + expr->print() + ";";
}

void* ReturnStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitReturnStmt(this, arg);
}

std::string ContinueStmt::print() {
    if (label == nullptr) return "continue";
    return "continue " + *label;
}

void* ContinueStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitContinueStmt(this, arg);
}

std::string BreakStmt::print() {
    if (label == nullptr) return "break";
    return "break " + *label;
}

void* BreakStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitBreakStmt(this, arg);
}

std::string DoWhile::print() {
    return "do" + body->print() + "\nwhile(" + expr->print() + ");";
}

void* DoWhile::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitDoWhile(this, arg);
}

std::string ThrowStmt::print() {
    return "throw " + expr->print() + ";";
}

void* ThrowStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitThrowStmt(this, arg);
}

std::string CatchStmt::print() {
    return "catch(" + param.print() + ")" + block->print();
}

void* CatchStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitCatchStmt(this, arg);
}

std::string TryStmt::print() {
    return "try " + block->print() + join(catches, "\n");
}

void* TryStmt::accept(Visitor<void*, void*>* v, void* arg){
  return v->visitTryStmt(this, arg);
}