import own/common
import std/it

//A move of a value declared outside a loop is emitted once but runs on every
//iteration. It is only sound when every path from the move leaves the loop
//(break/return), or when the place is reinitialized before the next
//iteration; Own::check_loop_moves rejects the rest (tests/fail/loop_move_*).
//This file is the allowed side, and it checks the value is still dropped
//exactly once: the moved-away value by the callee, the last one by the
//variable's own drop at the end of the function.

func move_then_break(){
    let a = A::new(1);
    while(true){
        send(a);   //1: the loop body always breaks, so the move runs once
        break;
    }
}

func move_then_return(){
    let a = A::new(2);
    while(true){
        send(a);   //2: `return` leaves the loop like `break` does
        return;
    }
    printf("unreachable\n");
}

func move_then_reinit(){
    let i = 0;
    let a = A::new(3);
    while(i < 3){
        send(a);           //3, then 4, then 5
        a = A::new(4 + i); //fresh value for the next iteration
        i += 1;
    }
    //the last iteration ended with the reinit, so `a` is live and 6 is
    //dropped here (the same shape as tests/own/30loopreinit.x)
}

func move_then_break_foreach(){
    let a = A::new(7);
    let xs = [1, 2, 3];
    let items = xs[0..3];
    //the for-each desugar ends the loop body with the opaque
    //`std::internal_block!(id)`, so Exit used to read the body as falling
    //through and this break-only move was reported as repeated. The emitter
    //now hands the real exit to Own::add_scope (see Emitter::body_exit).
    for x in items{
        send(a);   //7: same as move_then_break, through a for-each
        break;
    }
}

func main(){
    reset();
    move_then_break();
    check_ids(1);

    reset();
    move_then_break_foreach();
    check_ids(7);

    reset();
    move_then_return();
    check_ids(2);

    reset();
    move_then_reinit();
    assert(ids.len() == 4);
    assert(ids.pop_front() == 3);
    assert(ids.pop_front() == 4);
    assert(ids.pop_front() == 5);
    assert(ids.pop_front() == 6);   //the value the last iteration left in `a`

    reset();
    print("loop move done\n");
}
