#drop
struct Inner{ cnt: i32*; }
impl Drop for Inner{
    func drop(*self){ *self.cnt += 1; }
}
struct Mid{ inner: Inner; n: i32; }
struct Outer{ mid: Mid; }
struct Plain{ n: i32; }

//drop-ness reaches through fields (Outer -> Mid -> Inner) and is memoized per
//type: returning from this function must drop exactly one Inner, while Plain
//has nothing to drop.
func run(drops: i32*): i32{
    let p = Plain{n: 1};
    let o = Outer{mid: Mid{inner: Inner{cnt: drops}, n: 3}};
    return o.mid.n + p.n;
}

func main(){
    let drops = 0;
    assert(run(&drops) == 4);
    assert(drops == 1);
    assert(run(&drops) == 4);
    assert(drops == 2);
    print("drop memo done\n");
}
