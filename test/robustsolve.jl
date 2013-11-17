using JuMP
using Base.Test
using Gurobi

function Test1()
  m = RobustModel()
  @defVar(m, x[1:2] >= 0)
  @defUnc(m, 0.3 <= u <= 0.5)
  setObjective(m, :Max, x[1] + x[2])
  addConstraint(m, u*x[1] + 1*x[2] <= 2.)
  addConstraint(m, 1*x[1] + 1*x[2] <= 6.)
  status = solve(m)
  @test_approx_eq getValue(x[1]) 4.0
  @test_approx_eq getValue(x[2]) 0.0
end

function Test2()
  m = RobustModel()
  @defVar(m, x[1:2] >= 0)
  @defUnc(m, 0.3 <= u1 <= 0.5)
  @defUnc(m, 0.0 <= u2 <= 2.0)
  setObjective(m, :Max, x[1] + x[2])
  addConstraint(m, u1*x[1] + 1*x[2] <= 2.)
  addConstraint(m, u2*x[1] + 1*x[2] <= 6.)
  status = solve(m)
  @test_approx_eq getValue(x[1]) (2.0+2.0/3.0)
  @test_approx_eq getValue(x[2]) (    2.0/3.0)
end

function Test3()
  m = RobustModel()
  @defVar(m, x[1:2] >= 0)
  @defUnc(m, 0.3 <= u1 <= 1.5)
  @defUnc(m, 0.5 <= u2 <= 1.5)
  setObjective(m, :Max, x[1] + x[2])
  addConstraint(m, u1*x[1] <= 1)
  addConstraint(m, u2*x[2] <= 1)
  addConstraint(m, (2.0*u1-2.0) + (4.0*u2-2.0) <= +1)
  addConstraint(m, (2.0*u1-2.0) + (4.0*u2-2.0) >= -1)
	status = solve(m)
  @test_approx_eq getValue(x[1]) (2.0/3.0)
  @test_approx_eq getValue(x[2]) (10.0/11.0)
end

function Test4()
  m = RobustModel()
  @defVar(m, x >= 0)
  @defUnc(m, 3.0 <= u <= 4.0);
  setObjective(m, :Max, 1.0x)
  addConstraint(m, 1.0*x <= 1.0*u)
  status = solve(m)
  @test_approx_eq getValue(x) 3.0
end

Test1()
Test2()
Test3()
Test4()
