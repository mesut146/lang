import std/fs
import std/result

import ast/ast
import ast/parser
import ast/lexer

static find_type = Option<str>::new();

func main(){
    print("find usages()\n");
    print("pwd={:?}\n", current_dir()?);
    find_type = Option::new("TargetMachine");
    find_usage("../src/parser");
}

func find_usage(dir: str){
    let ignore = Option<str>::new();
    ignore = Option::new("bridge.x");
    for name in File::read_dir(dir).unwrap(){
        if(!name.str().ends_with(".x")) continue;
        if(ignore.is_some() && ignore.get().eq(name.str())) continue;
        let file = format("{}/{}", dir, name);
        print("file={:?}\n", file);
        let p = Parser::from_path(file);
        let unit = p.parse_unit();
        for item in &unit.items{
            visit_item(item);
        }
        unit.drop();
    }
}

func visit_type(node: Type*){
    //print("visit_type {:?}\n", node);
    if(find_type.is_none()) return;
    match node{
        Type::Simple(smp) => {
            if(find_type.get().eq(smp.name.str())){
                print("visit_type {:?}\n", node);
            }
        },
        Type::Pointer(ty) => visit_type(ty.get()),
        Type::Array(ty, size) => visit_type(ty.get()),
        Type::Slice(ty) => visit_type(ty.get()),
        Type::Function(ft) => {
            visit_type(&ft.get().return_type);
            for prm in &ft.get().params{
                visit_type(prm);
            }
        },
        Type::Lambda(lt) => {
            if(lt.get().return_type.is_some()){
                visit_type(lt.get().return_type.get());
            }
            for prm in &lt.get().params{
                visit_type(prm);
            }
        },
        Type::Tuple(tt) => {
            for ty in &tt.types{
                visit_type(ty);
            }
        }
    }
}

func visit_item(item: Item*){
    match item{
        Item::Impl(imp) => {
            visit_type(&imp.info.type);
            if(imp.info.trait_name.is_some()){
                visit_type(imp.info.trait_name.get());
            }
            for m in &imp.methods{
                visit_method(m);
            }
        },
        Item::Method(m)=>{
            visit_method(m);
        },
        Item::Type(alias, rhs)=>{
            visit_type(rhs);
        },
        Item::Glob(gl)=>{
            if(gl.type.is_some()){
                visit_type(gl.type.get());
            }
            visit_expr(&gl.expr);
        },
        Item::Const(cn)=>{
            if(cn.type.is_some()){
                visit_type(cn.type.get());
            }
            visit_expr(&cn.rhs);
        },
        Item::Decl(d)=>{
            visit_type(&d.type);
            if(d.base.is_some()){
                visit_type(d.base.get());
            }
            match d{
                Decl::Struct(fields)=>{
                    for fd in fields{
                        visit_type(&fd.type);
                    }
                },
                Decl::Enum(variants)=>{
                    for ev in variants{
                        for fd in &ev.fields{
                            visit_type(&fd.type);
                        }                                
                    }
                },                        
                Decl::TupleStruct(fields)=>{
                    for fd in fields{
                        visit_type(&fd.type);
                    }
                }                     
            }
        },
        Item::Extern(methods)=>{
            for m in methods{
                visit_method(m);
            }
        },
        Item::Module(md)=>{
            for it2 in &md.items{
                visit_item(it2);
            }
        },
        Item::Trait(tr)=>{
            visit_type(&tr.type);
        },
        _=>{}
    }
}

func visit_method(m: Method*){
    visit_type(&m.type);
    for prm in &m.params{
        visit_type(&prm.type);
    }
    if(m.body.is_some()){
        visit_block(m.body.get());
    }
}

func visit_block(b: Block*){
    for st in &b.list{
        visit_stmt(st);
    }
    if(b.return_expr.is_some()){
        visit_expr(b.return_expr.get());
    }
}

func visit_stmt(st: Stmt*){
    match st{
        Stmt::Var(ve)=>{
            visit_var(ve);
        },
        Stmt::Expr(e) => {
            visit_expr(e);
        },
        Stmt::Ret(e)=>{
            if(e.is_some()){
                visit_expr(e.get());
            }
        },
        Stmt::While(cond, then)=>{
            visit_expr(cond);
            visit_body(then.get());
        },
        Stmt::For(fs)=>{
            if(fs.var_decl.is_some()){
                visit_var(fs.var_decl.get());
            }
            if(fs.cond.is_some()){
                visit_expr(fs.cond.get());
            }
            for up in &fs.updaters{
                visit_expr(up);
            }
            visit_body(fs.body.get());
        },
        Stmt::ForEach(fe)=>{
            visit_expr(&fe.rhs);
            visit_block(&fe.body);
        },
        _=>{}
    }
}

func visit_var(ve: VarExpr*){
    for f in &ve.list{
        if(f.type.is_some()){
            visit_type(f.type.get());
        }
        visit_expr(&f.rhs);
    }
}

func visit_body(body: Body*){
    match body {
        Body::Block(b) => visit_block(b),
        Body::Stmt(e) => visit_stmt(e),
        Body::If(e) => visit_if(e),
        Body::IfLet(e) => visit_iflet(e),
    }
}

func visit_if(node: IfStmt*){
    visit_expr(&node.cond);
    visit_body(node.then.get());
    if(node.else_stmt.is_some()){
        visit_body(node.else_stmt.get());
    }
}

func visit_iflet(node: IfLet*){
    visit_type(&node.type);
    visit_expr(&node.rhs);
    visit_body(node.then.get());
    if(node.else_stmt.is_some()){
        visit_body(node.else_stmt.get());
    }
}


func visit_expr(node: Expr*){
    match node{
        Expr::Call(mc) =>{
            if(mc.scope.is_some()){
                visit_expr(mc.scope.get());
            }            
            for arg in &mc.args{
                visit_expr(arg);
            }
        },
        Expr::MacroCall(mc) =>{
            if(mc.scope.is_some()){
                visit_type(mc.scope.get());
            }
            for arg in &mc.args{
                visit_expr(arg);
            }
        },        
        Expr::Par(e) => visit_expr(e.get()),
        Expr::Type(ty) => visit_type(ty),
        Expr::Unary(op, e) => visit_expr(e.get()),
        Expr::Infix(op, l, r) => {
            visit_expr(l.get());
            visit_expr(r.get());
        },
        Expr::Access(scope, name) => visit_expr(scope.get()),
        Expr::Obj(ty, args) => {
            visit_type(ty);
            for arg in args{
                visit_expr(&arg.expr);
            }
        },
        Expr::As(lhs, ty) => {
            visit_expr(lhs.get());
            visit_type(ty);
        },
        Expr::Is(lhs, rhs) => {
            visit_expr(lhs.get());
            visit_expr(rhs.get());
        },
        Expr::Array(list, size) => {
            for e in list{
                visit_expr(e);
            }
        },
        Expr::ArrAccess(aa) => {
            visit_expr(aa.arr.get());
            visit_expr(aa.idx.get());
            if(aa.idx2.is_some()){
                visit_expr(aa.idx2.get());
            }
        },
        Expr::Match(me) => {
            visit_match(me.get());
        },
        Expr::Block(bl) => visit_block(bl.get()),
        Expr::If(is) => visit_if(is.get()),
        Expr::IfLet(is) => visit_iflet(is.get()),
        Expr::Lambda(lm) => {
            for prm in &lm.params{
                if(prm.type.is_some()){
                    visit_type(prm.type.get());
                }
            }
            if(lm.return_type.is_some()){
                visit_type(lm.return_type.get());
            }
            match lm.body.get(){
                LambdaBody::Expr(e) => visit_expr(e),
                LambdaBody::Stmt(e) => visit_stmt(e),
            }
        },
        Expr::Ques(e) => visit_expr(e.get()),
        Expr::Tuple(list) => {
            for ch in list{
                visit_expr(ch);
            }
        },
        _ => {}
    }
}

func visit_match(node: Match*){
    visit_expr(&node.expr);
    for mc in &node.cases{
        match &mc.rhs{
            MatchRhs::EXPR(e) => visit_expr(e),
            MatchRhs::STMT(e) => visit_stmt(e),
        }
    }
}