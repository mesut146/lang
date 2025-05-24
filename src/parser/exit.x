import parser/ast
import parser/resolver

enum ExitType {
    NONE,
    RETURN,
    BLOCK_RETURN,
    PANIC,
    BREAK,
    CONTINE,
    EXITCALL,
    UNREACHABLE
}

struct Exit {
    kind: ExitType;
    if_kind: Ptr<Exit>;
    else_kind: Ptr<Exit>;
    cases: List<Exit>;
}

impl Exit{
    func new(kind: ExitType): Exit{
        return Exit{
            kind: kind,
            if_kind: Ptr<Exit>::new(),
            else_kind: Ptr<Exit>::new(),
            cases: List<Exit>::new()
        };
    }
    func is_unreachable2(self): bool{
        for cs in &self.cases{
            if(!cs.is_unreachable()){
                return false;
            }
        }
        return true;
    }
    func is_return2(self): bool{
        for cs in &self.cases{
            if(!cs.is_return()){
                return false;
            }
        }
        return true;
    }
    func is_panic2(self): bool{
        for cs in &self.cases{
            if(!cs.is_panic()){
                return false;
            }
        }
        return true;
    }
    func is_exit2(self): bool{
        for cs in &self.cases{
            if(!cs.is_exit()){
                return false;
            }
        }
        return true;
    }
    func is_jump2(self): bool{
        for cs in &self.cases{
            if(!cs.is_jump()){
                return false;
            }
        }
        return true;
    }
    func is_none(self): bool{
        return self.kind is ExitType::NONE && self.if_kind.is_none() && self.else_kind.is_none() && self.cases.empty();
    }
    func is_unreachable(self): bool{
        if (self.kind is ExitType::UNREACHABLE) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_unreachable() && self.else_kind.get().is_unreachable();
        if(!self.cases.empty()) return self.is_unreachable2();
        return false;
    }
    func is_return(self): bool{
        if (self.kind is ExitType::RETURN) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_return() && self.else_kind.get().is_return();
        if(!self.cases.empty()) return self.is_return2();
        return false;
    }
    func is_panic(self): bool{
        if (self.kind is ExitType::PANIC) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_panic() && self.else_kind.get().is_panic();
        if(!self.cases.empty()) return self.is_panic2();
        return false;
    }
    func is_exit(self): bool{
        if (self.kind is ExitType::RETURN || self.kind is ExitType::PANIC || self.kind is ExitType::EXITCALL) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_exit() && self.else_kind.get().is_exit();
        if(!self.cases.empty()) return self.is_exit2();
        return false;
    }
    func is_jump(self): bool{
        if (self.kind is ExitType::RETURN || self.kind is ExitType::PANIC || self.kind is ExitType::BREAK || self.kind is ExitType::CONTINE || self.kind is ExitType::EXITCALL) return true;
        if (self.if_kind.is_some() && self.else_kind.is_some()) return self.if_kind.get().is_jump() && self.else_kind.get().is_jump();
        if(!self.cases.empty()) return self.is_jump2();
        return false;
    }

    func get_exit_type(rhs: MatchRhs*): Exit{
        match rhs{
            MatchRhs::EXPR(e) => return get_exit_type(e),
            MatchRhs::STMT(st) => return get_exit_type(st),
        }
    }

    func get_exit_type(body: Body*): Exit{
        match body{
            Body::Block(b) => return get_exit_type(b),
            Body::Stmt(st) => return get_exit_type(st),
            Body::If(st) => return get_exit_type(st),
            Body::IfLet(st) => return get_exit_type(st),
        }
    }

    func get_exit_type(block: Block*): Exit{
        if(block.return_expr.is_some()){
            let res = get_exit_type(block.return_expr.get());
            if(!res.is_none()){
                return res;
            }
            res.drop();
            return Exit::new(ExitType::BLOCK_RETURN);
        }
        if(block.list.empty()){
            return Exit::new(ExitType::NONE);
        }
        let last = block.list.last();
        return get_exit_type(last);
    }

    func get_exit_type(node: IfStmt*): Exit{
        let res = Exit::new(ExitType::NONE);
        res.if_kind = Ptr::new(get_exit_type(node.then.get()));
        if(node.else_stmt.is_some()){
            res.else_kind = Ptr::new(get_exit_type(node.else_stmt.get()));
        }
        return res;
    }

    func get_exit_type(node: IfLet*): Exit{
        let res = Exit::new(ExitType::NONE);
        res.if_kind = Ptr::new(get_exit_type(node.then.get()));
        if(node.else_stmt.is_some()){
            res.else_kind = Ptr::new(get_exit_type(node.else_stmt.get()));
        }
        return res;
    }
    
    func get_exit_type(node: Match*): Exit{
        let res = Exit::new(ExitType::NONE);
        for cs in &node.cases{
            res.cases.add(get_exit_type(&cs.rhs));
        }
        return res;
    }

    func get_exit_type(expr: Expr*): Exit{
        match expr{
            Expr::Block(blk) => {
                return get_exit_type(blk.get());
            },
            Expr::If(is) => {
                return get_exit_type(is.get());
            },
            Expr::IfLet(iflet0) => {
                let iflet = iflet0.get();
                return get_exit_type(iflet);
            },
            Expr::Match(mt0) => {
                return get_exit_type(mt0.get());
            },
            Expr::Call(call) => {
                if(call.name.eq("panic") && call.scope.is_none()){
                    return Exit::new(ExitType::PANIC);
                }
                if(call.name.eq("exit") && call.scope.is_none()){
                    return Exit::new(ExitType::EXITCALL);
                }
                if(Resolver::is_call(call, "std", "unreachable")){
                    return Exit::new(ExitType::UNREACHABLE);
                }
                return Exit::new(ExitType::NONE);
            },
            Expr::MacroCall(call) => {
                if(call.name.eq("panic") && call.scope.is_none()){
                    return Exit::new(ExitType::PANIC);
                }
                if(Resolver::is_call(call, "std", "unreachable")){
                    return Exit::new(ExitType::UNREACHABLE);
                }
                return Exit::new(ExitType::NONE);
            },
            _ => return Exit::new(ExitType::NONE)
        }
    }

    func get_exit_type(stmt: Stmt*): Exit{
        match stmt{
            Stmt::Ret(expr) => return Exit::new(ExitType::RETURN),
            Stmt::Break => return Exit::new(ExitType::BREAK),
            Stmt::Continue => return Exit::new(ExitType::CONTINE),
            Stmt::Expr(expr) => return get_exit_type(expr),
            _ => return Exit::new(ExitType::NONE),
        }
    }
}