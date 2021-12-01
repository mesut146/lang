#include "parser/Ast.h"
#include "parser/Util.h"

std::string SimpleName::print() {
    return name;
}

std::string QName::print() {
    return scope->print() + "." + name;
}

std::string Literal::print() {
    std::string s;
    s.append(val);
    return s;
}

std::string VarDecl::print() {
    std::string s;
    s.append(isVar ? "var" : "let");
    s.append(" ");
    s.append(join(list, ", "));
    s.append(";");
    return s;
}

std::string VarDeclExpr::print() {
    std::string s;
    s.append(isVar ? "var" : "let");
    s.append(" ");
    s.append(join(list, ", "));
    return s;
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

std::string Block::print() {
    std::string s;
    s.append("{\n");
    for (int i = 0; i < list.size(); ++i) {
        printBody(s, list[i]);
    }
    s.append("\n}");
    return s;
}

std::string EnumDecl::print() {
    std::string s;
    s.append("enum ");
    s.append(*name);
    s.append("{\n");
    s.append(join(cons, ",\n", "  "));
    s.append("\n}");
    return s;
}

std::string SimpleType::print() {
    return *type;
}

std::string RefType::print() {
    std::string s;
    s.append(name->print());
    if (!typeArgs.empty()) {
        s.append("<");
        s.append(join(typeArgs, ", "));
        s.append(">");
    }
    return s;
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

std::string Param::print() {
    std::string s;
    s.append(name);
    if (isOptional)
        s.append("?");
    s.append(": ");
    s.append(type->print());
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

std::string ParExpr::print() {
    return std::string("(" + expr->print() + ")");
}

std::string ObjExpr::print() {
    std::string s;
    s.append(name);
    s.append("{");
    s.append(join(entries, ", "));
    s.append("}");
    return s;
}

std::string AnonyObjExpr::print() {
    std::string s;
    s.append("{");
    s.append(join(entries, ", "));
    s.append("}");
    return s;
}

std::string Entry::print() {
    return key->print() + ":" + value->print();
}


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

std::string ImportStmt::print() {
    std::string s;
    s.append("import ");
    s.append(*file);
    if (as != nullptr) {
        s.append(" as ");
        s.append(*as);
    }
    return s;
}

std::string IfStmt::print() {
    std::string s;
    s.append("if(").append(expr->print()).append(")").append(thenStmt->print());
    if (elseStmt != nullptr) {
        s.append("else ").append(elseStmt->print());
    }
    return s;
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

std::string Infix::print() {
    return left->print() + " " + op + " " + right->print();
}

std::string Assign::print() {
    return left->print() + " " + op + " " + right->print();
}

std::string Unary::print() {
    return op + expr->print();
}

std::string Postfix::print() {
    return expr->print() + op;
}

std::string FieldAccess::print() {
    if (isOptional) {
        return scope->print() + "?." + name;
    }
    return scope->print() + "." + name;
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

std::string ArrayAccess::print() {
    if (isOptional) {
        return array->print() + "?[" + index->print() + "]";
    }
    return array->print() + "[" + index->print() + "]";
}

std::string ArrayExpr::print() {
    return "[" + join(list, ", ") + "]";
}
std::string Ternary::print() {
    return cond->print() + "?" + thenExpr->print() + ":" + elseExpr->print();
}

std::string WhileStmt::print() {
    return "while(" + expr->print() + ")\n" + body->print();
}

std::string ReturnStmt::print() {
    if (expr == nullptr) return "return";
    return "return " + expr->print() + ";";
}

std::string ContinueStmt::print() {
    if (label == nullptr) return "continue";
    return "continue " + *label;
}

std::string BreakStmt::print() {
    if (label == nullptr) return "break";
    return "break " + *label;
}

std::string DoWhile::print() {
    return "do" + body->print() + "\nwhile(" + expr->print() + ");";
}

std::string ThrowStmt::print() {
    return "throw " + expr->print() + ";";
}

std::string CatchStmt::print() {
    return "catch(" + param.print() + ")" + block->print();
}

std::string TryStmt::print() {
    return "try " + block->print() + join(catches, "\n");
}