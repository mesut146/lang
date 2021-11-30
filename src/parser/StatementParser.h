#pragma once

#include "Ast.h"

class Parser;

Statement *parseStmt(Parser *);
Block *parseBlock(Parser *p);