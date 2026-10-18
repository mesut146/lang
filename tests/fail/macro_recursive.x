// should-fail: macro expansion too deep
macro r(){
    r!();
}
func main(){
    r!();
}
