using JuMP
using Base.Test

# Test models

function Test1()
  m = RobustModel(:Max)

  x1 = Variable(m, 0, Inf, 0, "x1") #@defVar(m, x1 >= 0)
  x2 = Variable(m, 0, Inf, 0, "x2") #@defVar(m, x2 >= 0)
  u = Uncertain(m, 0.3, 0.5, "u")

  m.obj = x1 + x2

  addConstraint(m, u*x1 + 1*x2 <= 2.)
  addConstraint(m, 1*x1 + 1*x2 <= 6.)

  println(m)

  status = solve(m)

  #println(getValue(x1))
  #println(getValue(x2))
  #@test_approx_eq getValue(x1) 4.0
  #@test_approx_eq getValue(x2) 0.0
end

Test1()
