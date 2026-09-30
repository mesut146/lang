// should-fail: is not enum
func main(){
    let x = match 5{
        _ => 1,
    };
}
