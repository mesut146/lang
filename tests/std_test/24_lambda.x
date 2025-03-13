func main(){
    let l = List<i32>::new();
    l.add(5);
    l.add(10);
    l.add(15);
    
    print("find={}\n", l.find(f));
    let i = l.find(|a: i32*|: bool{
        return *a == 15;
    });
    print("find2={}\n", i);
    
    filter();
}

func f(a: i32*): bool{
    return *a == 10;
}

func filter(){
    let l = List<i32>::new();
    l.add_slice([3,4,7,9,11,12,13,14][0..8]);
    let f = l.filter(|a: i32*|: bool{
        return *a % 2 == 0;
    });
    
    for e in &f{
        let ee = **e;
        print("filter={}\n", ee);
    }
    
}