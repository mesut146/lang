import importTest/cls

func main(){
  let c = Point{x: 100, y: 200};
  assert c.x == 100 && c.y == 200;

  let c2 = Point::new(10, 20);
  assert c2.getX() == 10 && c2.getY() == 20;
  
  print("importTest done\n");
}