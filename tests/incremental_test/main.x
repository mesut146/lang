import incremental_test/a
import incremental_test/b
import incremental_test/macros

func main(){
   let a = getA();
   let b = getB();
   let c = C{10};
   let b2 = B{10, 20};
   //cross-unit macro: defined in macros.x, whose own import (mhelper.x) is not
   //imported here -- the expansion still resolves H and h_seven
   build_h!(30, 5);
   //scoped call into a module of an imported unit
   toolkit::build_pair!(9);
   printf("incremental done\n");
}