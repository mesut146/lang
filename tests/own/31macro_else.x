import own/common

//The else branch moves `a` through a user macro expansion. The join then has
//to drop the value on the *then* path (the else-moved value is consumed on
//both paths), and the pass that decides that -- Own::end_scope_if, which
//re-analyzes the else body with OwnVisitor -- has to walk the expansion block
//the resolver kept in format_map.
//
//Pre-fix red: OwnVisitor::visit_expr dispatched only Expr::Call/Obj/Infix, and
//user macro calls parse as Expr::MacroCall, so the else scope never recorded
//the move: branch(true) leaked `a` (no drop, check_ids(1) fails 0 != 1). The
//plain `send(a)` spelling in tests/own/13iflet_move.x-style code was always
//fine; only the expansion shape was invisible.
macro take_a(x: Expr){
    send(x);
}

func branch(cond: bool){
    let a = A::new(1);
    if(cond){
        print("then\n");
    }else{
        take_a!(a);
    }
}

func main(){
    //then path: the value the else moved drops at the join
    reset();
    branch(true);
    check_ids(1);
    //else path: send() dropped it, the join is on the then path only
    reset();
    branch(false);
    check_ids(1);
    print("macro else branch done\n");
}
