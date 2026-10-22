//`Token.value` is a slice of the source now (batch 20), not one owned String
//per token: it points into the Lexer's buffer -- or into the Lexer's scratch
//list for a string literal whose escapes were rewritten -- and the parser only
//copies where the text is stored in the AST (`Param` names, `Expr::Access`
//indices, comments, `popv`). An off-by-one span, a slice into a freed or moved
//buffer, or a scratch entry that did not survive its List growth would silently
//change identifiers, operators, numbers, literals or error text. This pins
//every lexer path that hands text to the parser: identifiers with digits and
//underscores glued to operators, multi-char operators, hex/float/underscored/
//suffixed numbers, char and escaped string literals, several literals in one
//file (scratch growth), comments between tokens, enum discriminants, array
//sizes and parameter names.
import std/io

#repr(i32)
enum Level{
  Low = 3,
  Mid,
  High = 9,
}

//the array size goes through `i32::parse(tok.value)`
struct Buf{
  bytes: [u8; 4];
}

//param names go through `Param{name: tok.value.owned()}`
func add_two(first_1: i32, second_2: i32): i32{
  return first_1 + second_2;
}

func main(){
  //identifiers with digits/underscores, every token glued to the next
  let x1_2=5;let _tmp9=7;
  assert(x1_2+_tmp9==12);
  assert(add_two(2,3)==5);

  //one- and two-char operators, comparison and compound assignment
  let a=1;let b=2;
  assert(a+b==3&&b-a==1);
  assert(a<b||a>b==false);
  assert(a!=b&&a<=b&&b>=a&&a<b&&b>a);
  a+=1;assert(a==2);
  a-=1;assert(a==1);
  a*=6;assert(a==6);
  a/=2;assert(a==3);
  assert(a%2==1);
  assert((1<<2)==4);
  assert((6&3)==2);
  assert((4|1)==5);
  assert(!false);

  //numbers: hex, underscored, float, suffixed, signed
  let h=0xFF;assert(h==255);
  let big=1_000;assert(big==1000);
  let f=1.5;assert(f==1.5);
  let f32v=2.25f32;assert(f32v==2.25);
  let i64v=3i64;assert(i64v==3);
  let neg=-5;assert(neg==-5);
  let negf=-2.5;assert(negf==-2.5);

  //char literals and escaped string literals (the Lexer scratch path);
  //two of them, so the scratch list grows between the slices
  let nl='\n';assert(nl=='\n');
  let quote='\'';assert(quote=='\'');
  let s="a\tb\"c\\d";
  assert(s.len()==7);
  assert(s.eq("a\tb\"c\\d"));
  let s2="x\ny";
  assert(s2.len()==3);
  assert(s2.eq("x\ny"));
  let empty="";assert(empty.len()==0);

  //comments between tokens must not disturb the slices around them
  let c=1/*mid*/+2; // trailing
  assert(c==3);
  /* leading */
  assert(c*2==6);

  //enum discriminants are parsed out of the token text
  let l0 = Level::Low as i32;
  let l1 = Level::Mid as i32;
  let l2 = Level::High as i32;
  assert(l0==3);
  assert(l1==4);
  assert(l2==9);

  //array size [u8; 4] is i32::parse(tok.value)
  let buf: Buf = Buf{bytes: [1u8; 4]};
  buf.bytes[3]=4u8;
  assert(buf.bytes[0]==1u8);
  assert(buf.bytes[3]==4u8);

  print("lexer token text ok\n");
}
