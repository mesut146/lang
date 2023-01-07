function c(){
  make && ./lang
}


function r(){
 #gcc a.x.o && ./a.out
 #clang-13 a.x.o && ./a.out
 clang-13 generic.x.o && ./a.out
}

$1
