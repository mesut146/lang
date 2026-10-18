import incremental_test/mhelper

//used from main.x, which imports this unit but not mhelper: the expansion must
//still see H and h_seven, because a foreign macro body is resolved with the
//imports of the unit that defines it
macro build_h(v: Expr, extra: i32){
    let h = H{v, extra};
    assert(h.n == v);
    assert(h.m == extra);
    assert(h_seven() == 7);
}
