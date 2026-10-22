//A function of another unit's module, called through the module path. This
//used to panic in get_decl while resolving the scope (RtKind::Module) and
//then reported a misleading "no such method" once the scope resolved.
//The asserted text includes the *declaring* unit's path: Desc.path is a slice
//into that unit's path String (borrowed, not copied -- see handoff.md), so a
//stale or dangling path shows up here instead of in the message only.
// should-fail: is in a module of another unit (tests/helpers/mod_owner.x)
import helpers/mod_owner

func main(){
    assert(m::helper() == 1);
}
