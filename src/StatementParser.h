#pragma once

#include "ExprParser.h"
#include "Util.h"

Statement *parseStmt(Parser *);
Block *parseBlock(Parser *p);