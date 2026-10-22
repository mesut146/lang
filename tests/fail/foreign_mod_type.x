//A `mod` member of an imported unit: `m` resolves (it is a module of
//another unit), but its members are only visible in the unit that declares
//them. This used to panic in get_decl (`get_decl() m=Desc{kind:
//RtKind::Module, ...}`) instead of reporting.
// should-fail: is a module of another unit (tests/helpers/mod_owner.x): a module's members are only visible in the unit that declares them
import helpers/mod_owner

func main(){
    let s: m::S = m::S{a: 1};
    assert(s.a == 1);
}
