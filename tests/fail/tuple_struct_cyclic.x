// should-fail: cyclic type
//A tuple field of the struct's own type is infinite size; the field validator
//has to run for positional fields too.
struct T(T);
func main(){
}
