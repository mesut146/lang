// should-fail: cyclic type S
//A struct that contains itself *by value* has infinite size. The drop query
//(DropHelper::is_drop_type/is_drop_decl) recursed forever on it -- SIGSEGV
//during handle_attr, before the field validator ran. A type already being
//expanded now contributes no drop-ness (`DropHelper::active`), so the
//validator's clean "cyclic type" error is what you get.
struct S{
  s: S;
}
func main(){
}
