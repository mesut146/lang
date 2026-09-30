// xfail: integer literals wider than 32 bits are rejected even with
// i64 context (use _i64 suffix); == itself is width-correct since promotion
func main(){
    let m = 1000000 as i64;
    let L = 1000000000000;
    assert(L == m * m);
}
