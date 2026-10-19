import own/common

//A generic whose type parameter is a drop type, met as a *field* of another
//decl. init visits declared types (so it instantiates Box2<A>) before it
//appends the derives, so the template's generated Drop impl does not exist
//yet: the instantiation's drop method has to wait for it (Resolver's
//pending_drops + the retry at the end of init).
//
//Pre-fix red: the compiler itself panicked, "no drop method for Box2<A>" in
//DropHelper::find_drop_impl, so this file did not even compile (see
//tests/normal/44-derive-clone.x, which had to avoid the shape).
struct Box2<T>{
    v: T;
    n: i32;
}

struct Outer{
    b: Box2<A>;
}

func scope(){
    let o = Outer{b: Box2<A>{v: A::new(1), n: 2}};
    o.b.v.check(1);
    assert(o.b.n == 2);
}

func main(){
    reset();
    scope();
    //the instantiated generic dropped its field exactly once
    check_ids(1);
    print("generic drop param done\n");
}
