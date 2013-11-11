using JuMP
using Base.Test

# Test models

function Test1()
  println("====================================")
  println("TEST 1")
  m = RobustModel(:Max)

  x1 = Variable(m, 0, Inf, 0, "x1") #@defVar(m, x1 >= 0)
  x2 = Variable(m, 0, Inf, 0, "x2") #@defVar(m, x2 >= 0)
  u = Uncertain(m, 0.3, 0.5, "u")

  m.obj = x1 + x2

  addConstraint(m, u*x1 + 1*x2 <= 2.)
  addConstraint(m, 1*x1 + 1*x2 <= 6.)

  println(m)

  status = solve(m)

  @test_approx_eq getValue(x1) 4.0
  @test_approx_eq getValue(x2) 0.0
end

function Test2()
  println("====================================")
  println("TEST 2")
  m = RobustModel(:Max)

  x1 = Variable(m, 0, Inf, 0, "x1") #@defVar(m, x1 >= 0)
  x2 = Variable(m, 0, Inf, 0, "x2") #@defVar(m, x2 >= 0)
  u1 = Uncertain(m, 0.3, 0.5, "u1")
  u2 = Uncertain(m, 0.0, 2.0, "u2")

  m.obj = x1 + x2

  addConstraint(m, u1*x1 + 1*x2 <= 2.)
  addConstraint(m, u2*x1 + 1*x2 <= 6.)

  println(m)

  status = solve(m)

  @test_approx_eq getValue(x1) (2.0+2.0/3.0)
  @test_approx_eq getValue(x2) (    2.0/3.0)
end

function Test3()
  println("====================================")
  println("TEST 3")
  m = RobustModel(:Max)

  x1 = Variable(m, 0, Inf, 0, "x1")
  x2 = Variable(m, 0, Inf, 0, "x2")
	
  u1 = Uncertain(m, 0.3, 1.5, "u1");
  u2 = Uncertain(m, 0.5, 1.5, "u2");

  m.obj = x1 + x2

  # Constraints
  addConstraint(m, u1*x1 <= 1)
  addConstraint(m, u2*x2 <= 1)

  # Uncertainty set
  addConstraint(m, (2.0*u1-2.0) + (4.0*u2-2.0) <= +1)
  addConstraint(m, (2.0*u1-2.0) + (4.0*u2-2.0) >= -1)
	
  println(m)

  status = solve(m)

  @test_approx_eq getValue(x1) (2.0/3.0)
  @test_approx_eq getValue(x2) (10.0/11.0)
end


function Test4()
  println("====================================")
  println("TEST 4")
  m = RobustModel(:Max)

  x = Variable(m, 0, Inf, 0, "x");
  u = Uncertain(m, 3.0, 4.0, "u");

  m.obj = 1.0*x;

  # Constraints
  addConstraint(m, 1.0*x -1.0*u <= 0.0)

  println(m)

  status = solve(m)

  @test_approx_eq getValue(x) 3.0
end



Test1()
Test2()
Test3()
Test4()
