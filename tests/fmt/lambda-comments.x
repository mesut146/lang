//regression: comments inside nested lambda bodies were hoisted to the
//top of the enclosing block (the let fragment line pointed past the
//lambda body). Each comment must stay in its own body.
func main(){
    // outer note
    let l1 = ||: void{
        // inner note
        let y = 22;
        let l2 = ||: i32{
            // deepest note
            let z = 33;
            return z; // trailing z
        };
        l2();
    };
    l1();
    print("lam ok\n");
}
