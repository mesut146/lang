//A function of another unit's module, called through the module path. This
//used to panic in get_decl while resolving the scope (RtKind::Module) and
//then reported a misleading "no such method" once the scope resolved.
// should-fail: is in a module of another unit
import helpers/mod_owner

func main(){
    assert(m::helper() == 1);
}
