static calls = [ID::NONE; 20];
static idx = 0;

enum ID{
    NONE, F, F2, G, G2, MEMBER, MEMBER2
}
func enter(id: ID){
    calls[idx] = id;
    ++idx;
}
func check(ids: [ID; 8]){
    assert(idx == ids.len());
    for(let i = 0;i < idx;++i){
        if(calls[i] is ids[i]){
            continue;
        }
        printf("check failed i=%d\n", i);
        exit(1);
    }
}

struct A{
    a: i64;
}
impl A{
    func member(){
        enter(ID::MEMBER);
        printf("A::member() ");
    }
    func member2(self){
        enter(ID::MEMBER2);
        printf("A::member2() ");
    }
}

func f(){
    enter(ID::F);
    printf("f() ");
}

func f2(){
    enter(ID::F2);
    printf("f2() ");
}

func g(a: i32): i32{
    enter(ID::G);
    printf("g(%d) ", a);
    return a * 2;
}

/*func g(a: A): A{
    enter(ID::G2);
    printf("g2(%d) ", a.a);
    return A{a: a.a * 2};
}*/

func take(fp: func() => void){
    printf("take ");
    fp();
}

func take2(fp: func(i32) => i32, val: i32): i32{
    let res = fp(val);
    printf("take2 %d ", res);
    return res;
}

func main(){
    let fp1 = f;
    fp1();

    let fp2 = fp1;
    fp2();

    fp1 = f2;
    fp1();

    let g2 = g;
    assert(g2(10) == 20);

    take(f);
    take(fp2);
    take(f2);

    assert(take2(g, 50) == 100);

    //let m1 = A::member;
    //m1();
    
    printf("\n");
    check([ID::F, ID::F, ID::F2, ID::G, ID::F, ID::F, ID::F2, ID::G]);
}