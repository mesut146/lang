import std/set

func main(){
    let set = Set<i32>::new();
    set.add(50);
    set.add(40);
    //set.add(10);
    //set.add(30);
    //set.add(12);
    //set.add(70);
    print("set={}\n", set);
    set.drop();
    print("set test done\n");
}