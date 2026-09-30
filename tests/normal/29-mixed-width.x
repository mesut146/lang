func main(){
    //mixed-width arithmetic promotes instead of truncating rhs to lhs
    let x = ((1 as i64) << 32) + 5;
    let y = 5;
    assert(x != y);
    assert(!(x == y));
    assert(y != x);
    assert(!(y == x));
    assert(x == ((1 as i64) << 32) + 5);
    //mixed arithmetic stays 64-bit (validated against literals
    //that fit; bigger ones need the _i64 suffix, see big_literal.x)
    let a = 100000 as i64;
    assert(a * a == 10000000000_i64);
    print("widths done\n");
}
