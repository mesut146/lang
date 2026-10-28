// should-fail: unary ~ on non integer
//`~` is the bitwise complement (xor with -1), so a bool has no meaning for it;
//the emitter would xor an i1. (A float would xor its bit pattern.)
func main(){
  let b = ~true;
}
