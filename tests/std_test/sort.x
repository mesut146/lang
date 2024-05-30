func str_test(){
    let s1 = "asd";
    let s2 = "ase";
    assert(Compare::compare(&s1, &s2) == -1);
    assert(Compare::compare(&s2, &s1) == 1);

    let s3 = "asd";
    assert(Compare::compare(&s1, &s3) == 0);
}

func list_i32(){
    let list = List<i32>::new();
    list.add(10);
    list.add(7);
    list.add(70);
    list.add(5);
    list.sort();
    let str = Fmt::str(&list);
    print("list = {}\n", str);
    assert(str.eq("[5, 7, 10, 70]"));
}
func list_str(){
    let list = List<String>::new();
    list.add("bxx".str());
    list.add("abc".str());
    list.add("abb".str());
    list.add("abd".str());
    list.add("cbd".str());
    
    list.sort();
    let str = Fmt::str(&list);
    print("list = {}\n", str);
    assert(str.eq("[abb, abc, abd, bxx, cbd]"));
}

func main(){
    str_test();
    list_i32();
    list_str();
    print("sort done\n");
}