#include "Parser.h"
#include "TypeUtils.h"
#include "Util.h"

std::string Parser::strLit() {
    auto t = consume(STRING_LIT);
    return std::string(t.value.begin() + 1, t.value.end() - 1);
}

ImportStmt parseImport(Parser *p) {
    ImportStmt res;
    p->consume(IMPORT);
    res.list.push_back(p->pop().value);
    while (p->is(DIV)) {
        p->pop();
        res.list.push_back(p->pop().value);
    }
    return res;
}

FieldDecl parseField(Parser *p) {
    int line = p->first()->line;
    auto name = p->name();
    p->consume(COLON);
    auto type = p->parseType();
    p->consume(SEMI);
    auto res = FieldDecl(name, type);
    res.line = line;
    return res;
}

// "class" name typeArgs? (":" type)? "{" member* "}"
std::unique_ptr<StructDecl> Parser::parseTypeDecl() {
    auto res = std::make_unique<StructDecl>();
    res->line = first()->line;
    res->unit = unit;
    if (is(CLASS)) {
        consume(CLASS);
    } else {
        consume(STRUCT);
    }
    res->type = parseType();
    if (!res->type.typeArgs.empty()) {
        res->isGeneric = true;
    }
    if (is(COLON)) {
        pop();
        res->base = parseType();
    }
    if (is(SEMI)) {
        consume(SEMI);
        return res;
    }
    consume(LBRACE);
    //members
    while (first() != nullptr && !is(RBRACE)) {
        if (is(IDENT)) {
            res->fields.push_back(parseField(this));
        } else {
            throw std::runtime_error("invalid class member: " + first()->print());
        }
    }
    consume(RBRACE);
    return res;
}

FieldDecl parseEnumParam(Parser *p) {
    auto name = p->name();
    p->consume(COLON);
    auto type = p->parseType();
    return FieldDecl{name, type};
}

EnumVariant parseEnumEntry(Parser *p) {
    EnumVariant res;
    res.name = p->name();
    if (p->is(LPAREN)) {
        p->consume(LPAREN);
        res.fields.push_back(parseEnumParam(p));
        while (p->is(COMMA)) {
            p->consume(COMMA);
            res.fields.push_back(parseEnumParam(p));
        }
        p->consume(RPAREN);
    }
    return res;
}

std::unique_ptr<EnumDecl> Parser::parseEnumDecl() {
    auto res = std::make_unique<EnumDecl>();
    res->unit = unit;
    if (is(HASH)) {
        pop();
        consume(IDENT);
        consume(LPAREN);
        res->derives.push_back(parseType());
        while (is(COMMA)) {
            consume(COMMA);
            res->derives.push_back(parseType());
        }
        consume(RPAREN);
    }
    consume(ENUM);
    res->type = parseType();
    if (!res->type.typeArgs.empty()) {
        res->isGeneric = true;
    }
    consume(LBRACE);
    if (!is(RBRACE)) {
        res->variants.push_back(parseEnumEntry(this));
        while (is(COMMA)) {
            consume(COMMA);
            res->variants.push_back(parseEnumEntry(this));
        }
    }
    consume(RBRACE);
    return res;
}

std::unique_ptr<Trait> parseTrait(Parser *p) {
    p->consume(TRAIT);
    auto type = p->parseType();
    auto res = std::make_unique<Trait>(type);
    res->unit = p->unit;
    p->consume(LBRACE);
    while (!p->is(RBRACE)) {
        res->methods.push_back(std::move(p->parseMethod()));
        res->methods.back().parent = res.get();
    }
    p->consume(RBRACE);
    return res;
}

std::unique_ptr<Impl> parseImpl(Parser *p) {
    p->consume(IMPL);
    std::vector<Type> type_params;
    if (p->is(LT)) {
        type_params = p->type_params();
    }
    auto type = p->parseType();
    auto res = std::make_unique<Impl>(type);
    res->type_params = type_params;
    res->unit = p->unit;
    if (p->is(FOR)) {
        res->trait_name.emplace(type);
        p->consume(FOR);
        res->type = p->parseType();
    } else {
        res->type = type;
    }
    p->consume(LBRACE);
    while (!p->is(RBRACE)) {
        auto m = p->parseMethod();
        m.parent = res.get();
        res->methods.push_back(std::move(m));
    }
    p->consume(RBRACE);
    return res;
}

std::unique_ptr<Extern> parseExtern(Parser *p) {
    auto res = std::make_unique<Extern>();
    p->consume(EXTERN);
    p->consume(LBRACE);
    while (!p->is(RBRACE)) {
        auto m = p->parseMethod();
        m.parent = res.get();
        res->methods.push_back(std::move(m));
    }
    p->consume(RBRACE);
    return res;
}

bool Parser::isVarDecl() {
    if (is({STATIC}, {LET, CONST_KW})) return true;
    return is({LET, CONST_KW});
}

bool Parser::isMethod() {
    return is(FUNC) || is({VIRTUAL}, {FUNC});
}

std::shared_ptr<Unit> Parser::parseUnit() {
    auto res = std::make_shared<Unit>();
    unit = res.get();
    unit->path = lexer.path;
    unit->lastLine = tokens.back().line;

    while (first() != nullptr && is(IMPORT)) {
        res->imports.push_back(parseImport(this));
    }

    while (first() != nullptr) {
        //top level decl
        std::vector<Type> derives;
        if (is(HASH)) {
            pop();
            consume(IDENT);
            consume(LPAREN);
            derives.push_back(parseType());
            while (is(COMMA)) {
                consume(COMMA);
                derives.push_back(parseType());
            }
            consume(RPAREN);
        }
        if (is({CLASS}) || is({STRUCT})) {
            auto td = parseTypeDecl();
            td->derives = derives;
            res->items.push_back(std::move(td));
        } else if (is(ENUM)) {
            auto ed = parseEnumDecl();
            ed->derives = derives;
            res->items.push_back(std::move(ed));
        } else if (is(TRAIT)) {
            res->items.push_back(parseTrait(this));
        } else if (is(IMPL)) {
            res->items.push_back(parseImpl(this));
        } else if (is(EXTERN)) {
            res->items.push_back(parseExtern(this));
        } else if (isMethod()) {
            res->items.push_back(std::make_unique<Method>(parseMethod()));
        } else if (is(TYPE)) {
            pop();
            auto name = pop().value;
            consume(EQ);
            auto rhs = parseType();
            consume(SEMI);
            auto ti = std::make_unique<TypeItem>(name, rhs);
            res->items.push_back(std::move(ti));
        } else {
            throw std::runtime_error("invalid top level decl: " + first()->print() + " line: " + std::to_string(first()->line));
        }
    }
    return res;
}

//name ":" type ("=" expr)?
Param Parser::parseParam() {
    auto nm = pop();
    Param res(nm.value);
    res.line = nm.line;
    consume(COLON);
    res.type = (parseType());
    return res;
}

Method Parser::parseMethod() {
    Method res(unit);
    if (is(VIRTUAL)) {
        res.isVirtual = true;
        pop();
    }
    consume(FUNC);
    auto nm = pop();
    res.line = nm.line;
    res.name = nm.value;
    if (is(LT)) {
        res.typeArgs = type_params();
        res.isGeneric = true;
    }
    consume(LPAREN);
    if (!is(RPAREN)) {
        if (is({IDENT}, {COLON})) {
            res.params.push_back(parseParam());
        } else {
            auto nm = pop();
            Param self(nm.value);
            self.line = nm.line;
            res.self = std::move(self);
        }
        while (is(COMMA)) {
            consume(COMMA);
            res.params.push_back(parseParam());
        }
    }
    consume(RPAREN);
    if (is(COLON)) {
        consume(COLON);
        res.type = (parseType());
    } else {
        //default is void
        res.type = (Type("void"));
    }
    if (is(SEMI)) {
        //interface
        consume(SEMI);
    } else {
        res.body = parseBlock();
    }
    return res;
}

//name (":" type)? ("=" expr)?;
Fragment frag(Parser *p) {
    Fragment res;
    res.line = p->first()->line;
    res.name = p->name();
    if (p->is(COLON)) {
        p->consume(COLON);
        res.type.emplace(p->parseType());
    }
    if (!p->is(EQ)) {
        throw std::runtime_error("variable " + res.name + " must have initializer");
    }
    p->consume(EQ);
    res.rhs.reset(p->parseExpr());
    return res;
}

//"let" varDeclFrag ("," varDeclFrag)*;
std::unique_ptr<VarDecl> Parser::parseVarDecl() {
    auto res = std::make_unique<VarDecl>();
    res->decl = parseVarDeclExpr();
    consume(SEMI);
    return res;
}

//varType varDeclFrag ("," varDeclFrag)*;
VarDeclExpr *Parser::parseVarDeclExpr() {
    auto res = new VarDeclExpr;
    if (is(STATIC)) {
        consume(STATIC);
        res->isStatic = true;
    }
    if (is(CONST_KW)) {
        consume(CONST_KW);
        res->isConst = true;
    } else {
        consume(LET);
    }
    res->list.push_back(frag(this));
    //rest if any
    while (is(COMMA)) {
        consume(COMMA);
        res->list.push_back(frag(this));
    }
    return res;
}

Type parse_tp(Parser *p) {
    auto res = Type(p->name());
    if (p->is(COLON)) {
        throw std::runtime_error("trait bound");
        //p->consume(COLON);
        //p->parseType();
    }
    return res;
}

std::vector<Type> Parser::type_params() {
    std::vector<Type> list;
    consume(LT);
    list.push_back(parse_tp(this));
    while (is(COMMA)) {
        consume(COMMA);
        list.push_back(parse_tp(this));
    }
    consume(GT);
    return list;
}