//discarded format!() result: the built String buffer must be freed. Raw
//malloc leak, invisible to the drop-count tracker (see bin/test.sh leak).
func main(){
  format!("discarded {}", 5);
  print("formatbang_discard done\n");
}
