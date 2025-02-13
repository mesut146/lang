func take<T>(fp: T, x: i32*){
    fp(10, x);
}

func take3<T>(fp: T/*, x: i32* */){
    fp(10);//fp(10, x)
}

func lambda(){
    let x = 55;
    let lm = |a: i32, x_: i32*|: i32{
        printf("from lambda %d %d\n", a, *x_);
        assert(a == 45);
        assert(*x_ == 55);
        *x_ += 1;
        return 77;
    };
    lm(45, &x);
    assert(x == 56);
    //take(lm, &x);
}

/*func capture(){
    let x = 55;
    let lm = |a: i32|: i32{
        printf("from lambda %d %d\n", a, x);
        x += 1;//*x+=1;
        assert(a == 45);
        assert(x == 55);//*x==55
        return 77;
    };
    lm(45);//lm(45, &x);
    assert(x == 56);
    take3(lm);//take3(lm, &x);
}*/

/*func lambda2(){
    let x = 11;
    let l1 = ||: void{
        let y = 22;
        let l2 = ||: i32{
            let z = 33;
            printf("l2 %d %d %d\n", x, y, z);
            let tmp = x + y + z;
            return z;
        };
        printf("l1 %d %d\n", x, y);
        let tmp = x + y;
    };
}*/


func main(){
    lambda();
    
}