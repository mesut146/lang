import std/string

//if-let over an owned temporary whose variant does not match: the
//temporary's payload String buffer must be freed. Raw malloc leak,
//invisible to the drop-count tracker (see bin/test.sh leak).
enum E{
  V{v: String},
  W
}

func get(b: bool): E{
  if(b){
    return E::V{v: format("hello {}", 1)};
  }
  return E::W;
}

func nomatch(){
  if let E::W = get(true){
    print("W\n");
  }
}

func main(){
  nomatch();
  print("iflet_temp done\n");
}
