#include "Ast.h"

template<class T>
std::string join(std::vector<T> &arr, const char *sep) {
  std::string s;
  for (int i = 0; i < arr.size(); i++) {
    s.append(arr[i].print());
    if (i < arr.size() - 1)
      s.append(sep);
  }
  return s;
}
template<class T>
std::string join(std::vector<T *> &arr, const char *sep) {
  std::string s;
  for (int i = 0; i < arr.size(); i++) {
    s.append(arr[i]->print());
    if (i < arr.size() - 1)
      s.append(sep);
  }
  return s;
}

std::string join(std::vector<std::string> &arr, const char *sep) {
  std::string s;
  for (int i = 0; i < arr.size(); i++) {
    s.append(arr[i]);
    if (i < arr.size() - 1)
      s.append(sep);
  }
  return s;
}

std::string SimpleName::print() {
  return *name;
}

std::string QName::print() {
  return scope->print() + "." + *name;
}

std::string Literal::print() {
  std::string s;
  s.append(val);
  return s;
}

std::string VarDecl::print() {
  std::string s;
  s.append(type->print());
  s.append(name);
  if (right != nullptr) {
    s.append("=");
    s.append(right->print());
  }
  return s;
}

std::string ExprStmt::print() {
  return expr->print() + ";";
}

/*std::string Field::print()
{
  return type->print() + " " + *name + (expr == nullptr ? "" : expr->print()) + ";";
}*/

std::string Block::print() {
  std::string s;
  s.append("{\n");
  s.append(join(list, "\n"));
  s.append("}");
  return s;
}

std::string EnumDecl::print() {
  std::string s;
  s.append("enum ");
  s.append(*name);
  s.append("{\n");
  s.append(join(cons, ",\n"));
  s.append("}");
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
  s.append(*name);
  s.append("{\n");
  s.append(join(fields, "\n"));
  s.append(join(methods, "\n"));
  s.append(join(types, "\n"));
  s.append("\n}");
  return s;
}

std::string Method::print() {
  std::string s;
  s.append(type->print());
  s.append(" ");
  s.append(name);
  s.append("(");
  s.append(join(params, " "));
  s.append(")");
  s.append(body.print());
  return s;
}

std::string Param::print() {
  std::string s;
  s.append(type->print());
  s.append(" ");
  s.append(*name);
  if (isOptional)
    s.append("?");
  if (defVal != nullptr) {
    s.append(" = ");
    s.append(defVal->print());
  }
  return s;
}

std::string ParExpr::print() {
  return std::string("(" + expr->print() + ")");
}

std::string Unit::print() {
  std::string s;
  s.append(join(imports, "\n"));
  s.append(join(methods, "\n"));
  s.append(join(stmts, "\n"));
  s.append(join(types, "\n"));
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
  if (!decl.empty()) {
    s.append(decl[0].print());
  }
  s.append(";");
  if (cond != nullptr) {
    s.append(cond->print());
  }
  s.append(";");
  if (!updaters.empty()) {
    s.append(join(updaters, ", "));
  }
  s.append(")\n");
  s.append(body->print());
  return s;
}

std::string ForEach::print() {
  std::string s;
  s.append("for(");
  s.append(decl.print());
  s.append(":");
  s.append(expr->print());
  s.append(")\n");
  s.append(body->print());
  return s;
}

std::string Infix::print() {
  return left->print() + " " + op + " " + right->print();
}
std::string Unary::print() {
  return op + expr->print();
}
std::string Postfix::print() {
  return expr->print() + op;
}
std::string NullLit::print() {
  return "null";
}
std::string FieldAccess::print() {
  return scope->print() + "." + name;
}
std::string MethodCall::print() {
  if (scope == nullptr) {
    return name + "(" + join(args, ", ") + ")";
  } else {
    return scope->print() + "." + name + "(" + join(args, ", ") + ")";
  }
}
std::string WhileStmt::print() {
  return "while(" + expr->print() + ")\n" + body->print();
}
