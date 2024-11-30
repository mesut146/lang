import std/llist

func main(){
    let l = LinkedList<i32>::new();
    l.add(10);
    l.add(20);
    l.add(5);
    print("l={}\n", l);
}