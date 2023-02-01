import List
import str

class String{
    arr: List<i8>;
}

impl String{
    func new(): String{
        return String{arr: List<i8>::new()};
    }
}